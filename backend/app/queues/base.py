"""Application-owned async queue interface (blueprint §11.2).

Domain logic depends only on this interface — **no Azure SDK imports here** or in any
caller. Concrete providers (`azure_queue`, `stub`) live behind it. Messages are wake
signals; the DB is authoritative (§4.2), so a lost/duplicate signal is always safe.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from app.queues.message import QueueMessage


@dataclass(frozen=True)
class ReceivedSignal:
    """A received wake signal plus the provider-specific handle needed to delete it."""

    message: QueueMessage
    receipt: object  # opaque provider handle (pop_receipt / stub id)
    dequeue_count: int = 0  # recorded when available; DB attempt_count is authoritative (§4.4)


class QueueProvider(ABC):
    """Send/receive/delete wake signals. All methods are async."""

    @abstractmethod
    async def send_signal(self, queue: str, message: QueueMessage) -> None:
        """Best-effort wake signal. Callers send AFTER the DB commit and must treat a
        failure as non-fatal — recovery re-signals within 5 minutes (§11.5)."""

    @abstractmethod
    async def receive_signals(
        self, queue: str, *, max_messages: int = 1, visibility_timeout: int = 60
    ) -> list[ReceivedSignal]:
        """Receive up to `max_messages`, hidden for `visibility_timeout` seconds."""

    @abstractmethod
    async def delete_signal(self, queue: str, signal: ReceivedSignal) -> None:
        """Delete a signal after a successful atomic DB claim, or when it is a
        stale/duplicate/terminal no-op (§4.4 steps 4–5)."""

    async def close(self) -> None:
        """Release provider resources. Default no-op."""
        return None
