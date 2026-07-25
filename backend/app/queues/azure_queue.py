"""Azure Storage Queue provider (blueprint §11.2, §11.13).

Prefers **managed identity** (`DefaultAzureCredential`); a connection string is a
documented fallback via secret config only (§11.13). The Azure SDK is imported
lazily so the base app + test suite run without `azure-storage-queue` installed
(the stub provider backs tests). Standard_LRS Storage Queue only — no Service Bus.
"""

from __future__ import annotations

from app.queues.base import QueueProvider, ReceivedSignal
from app.queues.message import QueueMessage


class AzureStorageQueue(QueueProvider):
    def __init__(
        self,
        *,
        account_name: str | None = None,
        queue_endpoint: str | None = None,
        connection_string: str | None = None,
    ) -> None:
        if not connection_string and not (account_name or queue_endpoint):
            raise ValueError(
                "AzureStorageQueue needs a connection string or an account name/endpoint"
            )
        self._account_name = account_name
        self._endpoint = queue_endpoint
        self._conn = connection_string
        self._clients: dict[str, object] = {}
        self._credential: object | None = None

    def _client(self, queue: str):  # noqa: ANN202 - lazy azure type
        cached = self._clients.get(queue)
        if cached is not None:
            return cached
        # Base64 so arbitrary JSON is transport-safe and KEDA counts messages plainly.
        from azure.storage.queue import TextBase64DecodePolicy, TextBase64EncodePolicy
        from azure.storage.queue.aio import QueueClient

        kwargs = {
            "message_encode_policy": TextBase64EncodePolicy(),
            "message_decode_policy": TextBase64DecodePolicy(),
        }
        if self._conn:
            client = QueueClient.from_connection_string(self._conn, queue, **kwargs)
        else:
            from azure.identity.aio import DefaultAzureCredential

            if self._credential is None:
                self._credential = DefaultAzureCredential()
            endpoint = self._endpoint or f"https://{self._account_name}.queue.core.windows.net"
            client = QueueClient(
                account_url=endpoint, queue_name=queue, credential=self._credential, **kwargs
            )
        self._clients[queue] = client
        return client

    async def send_signal(self, queue: str, message: QueueMessage) -> None:
        await self._client(queue).send_message(message.to_json())

    async def receive_signals(
        self, queue: str, *, max_messages: int = 1, visibility_timeout: int = 60
    ) -> list[ReceivedSignal]:
        client = self._client(queue)
        out: list[ReceivedSignal] = []
        async for msg in client.receive_messages(
            messages_per_page=max_messages,
            max_messages=max_messages,
            visibility_timeout=visibility_timeout,
        ):
            try:
                parsed = QueueMessage.from_json(msg.content)
            except Exception:
                # Undecodable/foreign message: hand it back so the worker can delete it
                # as a poison/stale signal (the DB claim is authoritative anyway).
                parsed = None  # type: ignore[assignment]
            out.append(
                ReceivedSignal(
                    message=parsed,  # type: ignore[arg-type]
                    receipt=(msg.id, msg.pop_receipt),
                    dequeue_count=int(getattr(msg, "dequeue_count", 0) or 0),
                )
            )
        return out

    async def delete_signal(self, queue: str, signal: ReceivedSignal) -> None:
        msg_id, pop_receipt = signal.receipt  # type: ignore[misc]
        await self._client(queue).delete_message(msg_id, pop_receipt)

    async def close(self) -> None:
        for client in self._clients.values():
            try:
                await client.close()  # type: ignore[attr-defined]
            except Exception:
                pass
        cred = self._credential
        if cred is not None:
            try:
                await cred.close()  # type: ignore[attr-defined]
            except Exception:
                pass
