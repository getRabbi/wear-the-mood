"""Queue abstraction: message versioning/validation, stub round-trip, routing,
best-effort enqueue, and Azure provider construction (blueprint §11.2, §11.15)."""

from __future__ import annotations

import asyncio

import pytest

from app.queues import (
    KIND_ENRICHMENT,
    KIND_REMBG,
    KIND_TRYON,
    enqueue_signal,
    queue_for_kind,
)
from app.queues.base import QueueProvider, ReceivedSignal
from app.queues.message import MESSAGE_VERSION, QueueMessage, QueueMessageError
from app.queues.stub import StubQueue


def test_message_roundtrip_and_version() -> None:
    m = QueueMessage.new(KIND_REMBG, "job-123", trace_id="t1")
    assert m.v == MESSAGE_VERSION
    back = QueueMessage.from_json(m.to_json())
    assert back == m
    assert '"v":1' in m.to_json()  # compact, no PII


def test_message_rejects_bad_version_kind_and_missing_id() -> None:
    with pytest.raises(QueueMessageError):
        QueueMessage.from_json('{"v":2,"kind":"rembg","job_id":"x"}')
    with pytest.raises(QueueMessageError):
        QueueMessage.from_json('{"v":1,"kind":"nope","job_id":"x"}')
    with pytest.raises(QueueMessageError):
        QueueMessage.from_json('{"v":1,"kind":"rembg"}')
    with pytest.raises(QueueMessageError):
        QueueMessage.from_json("not json")
    with pytest.raises(QueueMessageError):
        QueueMessage.new("bogus", "x")


def test_stub_send_receive_delete_roundtrip() -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("jobs", QueueMessage.new(KIND_REMBG, "a"))
        got = await q.receive_signals("jobs", max_messages=5, visibility_timeout=30)
        assert len(got) == 1 and got[0].message.job_id == "a"
        # Invisible until visibility timeout: a second receive sees nothing.
        assert await q.receive_signals("jobs") == []
        assert q.depth("jobs") == 1  # still present, just hidden
        await q.delete_signal("jobs", got[0])
        assert q.depth("jobs") == 0

    asyncio.run(run())


def test_queue_for_kind_routing() -> None:
    assert queue_for_kind(KIND_REMBG) == "jobs"
    assert queue_for_kind(KIND_ENRICHMENT) == "enrichment"
    assert queue_for_kind(KIND_TRYON) == "enrichment"


def test_enqueue_signal_best_effort() -> None:
    async def run() -> None:
        stub = StubQueue()
        assert await enqueue_signal(KIND_TRYON, "j1", provider=stub) is True
        assert stub.depth("enrichment") == 1

        class _Boom(QueueProvider):
            async def send_signal(self, queue, message):  # type: ignore[no-untyped-def]
                raise RuntimeError("queue down")

            async def receive_signals(self, queue, **kw):  # type: ignore[no-untyped-def]
                return []

            async def delete_signal(self, queue, signal):  # type: ignore[no-untyped-def]
                return None

        # Send failure must be swallowed and reported as False (recovery re-signals).
        assert await enqueue_signal(KIND_REMBG, "j2", provider=_Boom()) is False

    asyncio.run(run())


def test_azure_provider_construction_validates_without_sdk() -> None:
    # Importing + constructing must not require azure-storage-queue (lazy import).
    from app.queues.azure_queue import AzureStorageQueue

    with pytest.raises(ValueError):
        AzureStorageQueue()
    # Valid config constructs fine (no network / SDK touched until a call is made).
    assert AzureStorageQueue(connection_string="UseDevelopmentStorage=true") is not None
    assert AzureStorageQueue(account_name="wtmprodxyz") is not None


def test_received_signal_defaults() -> None:
    sig = ReceivedSignal(message=QueueMessage.new(KIND_ENRICHMENT, "z"), receipt="r")
    assert sig.dequeue_count == 0
