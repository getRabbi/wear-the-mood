"""Queue factory + kind→queue routing + best-effort enqueue (blueprint §11.2, §11.5)."""

from __future__ import annotations

import logging
from functools import lru_cache

from app.core.config import get_settings
from app.queues.base import QueueProvider, ReceivedSignal
from app.queues.message import (
    KIND_ENRICHMENT,
    KIND_REMBG,
    KIND_TRYON,
    QueueMessage,
    QueueMessageError,
)
from app.queues.stub import StubQueue

log = logging.getLogger("fashionos.queues")


def queue_for_kind(kind: str) -> str:
    """`rembg` cutouts wake the rembg worker on the `jobs` queue; try-on / AI jobs and
    post-cutout enrichment wake the orchestrator on the `enrichment` queue (§4.1, §11.4)."""
    s = get_settings()
    if kind == KIND_REMBG:
        return s.azure_queue_jobs
    return s.azure_queue_enrichment


@lru_cache(maxsize=1)
def get_queue_provider() -> QueueProvider:
    s = get_settings()
    provider = (s.queue_provider or "stub").strip().lower()
    if provider == "azure":
        from app.queues.azure_queue import AzureStorageQueue

        return AzureStorageQueue(
            account_name=s.azure_storage_account_name or None,
            queue_endpoint=s.azure_storage_queue_endpoint or None,
            connection_string=s.azure_storage_connection_string or None,
        )
    return StubQueue()


async def enqueue_signal(
    kind: str,
    job_id: str,
    *,
    provider: QueueProvider | None = None,
    trace_id: str | None = None,
) -> bool:
    """Best-effort wake signal sent AFTER the DB commit (§11.5).

    Returns True when sent, False on failure. A failure is non-fatal: the caller keeps
    the DB row queued and the 5-minute recovery task re-signals it. This never raises
    into the request path and must not run inside a DB transaction (§11.5).
    """
    p = provider or get_queue_provider()
    try:
        await p.send_signal(queue_for_kind(kind), QueueMessage.new(kind, job_id, trace_id=trace_id))
        return True
    except Exception as exc:  # noqa: BLE001 - best-effort; recovery is the backstop
        log.warning("queue signal failed (kind=%s job=%s): %s", kind, job_id, exc)
        return False


__all__ = [
    "QueueProvider",
    "ReceivedSignal",
    "QueueMessage",
    "QueueMessageError",
    "get_queue_provider",
    "queue_for_kind",
    "enqueue_signal",
    "KIND_REMBG",
    "KIND_ENRICHMENT",
    "KIND_TRYON",
]
