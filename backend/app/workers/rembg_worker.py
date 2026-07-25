"""RemBG worker entrypoint (Azure Container App ``wtm-rembg-worker``, blueprint §11.4).

Wakes on the ``jobs`` queue, atomically claims the referenced wardrobe cutout,
runs local background removal, marks the cutout ready, then emits ONE ``enrichment``
wake signal so the orchestrator does the slower tagging/embedding. Owns ONLY the
cutout critical path. The rembg model is baked into the image at build time so
startup never downloads it (§11.4, §11.11).

Run with: ``python -m app.workers.rembg_worker``
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.queues import KIND_ENRICHMENT, KIND_REMBG, enqueue_signal, get_queue_provider
from app.queues.base import QueueProvider, ReceivedSignal
from app.services.bg import prewarm_background_remover
from app.workers.bg_worker import process_cutout
from app.workers.claim import claim_cutout

log = logging.getLogger("fashionos.worker.rembg")

POLL_INTERVAL_SECONDS = 2
_VISIBILITY = 300  # a claimed rembg signal stays hidden this long while we process
_BATCH = 8


async def _mark_cutout_poison(conn: asyncpg.Connection, item_id: object) -> None:
    await conn.execute(
        "update public.wardrobe_items set cutout_status = 'failed', "
        "cutout_error_code = 'max_attempts' where id = $1::uuid",
        str(item_id),
    )


async def handle_signal(
    conn: asyncpg.Connection,
    provider: QueueProvider,
    signal: ReceivedSignal,
    queue: str,
    *,
    stale_seconds: int,
    max_attempts: int,
) -> None:
    msg = signal.message
    # Foreign/undecodable message or wrong kind → delete; DB is authoritative (§4.4).
    if msg is None or msg.kind != KIND_REMBG:
        await provider.delete_signal(queue, signal)
        return
    row = await claim_cutout(conn, msg.job_id, stale_seconds=stale_seconds)
    # Delete the signal now — after a successful claim (§4.4 step 5) OR as a
    # duplicate/stale/terminal no-op when unclaimable (§4.4 step 4).
    await provider.delete_signal(queue, signal)
    if row is None:
        return
    if row["attempt_count"] > max_attempts:
        await _mark_cutout_poison(conn, row["id"])
        log.error("rembg poison item=%s attempts=%s", row["id"], row["attempt_count"])
        return
    cutout = await process_cutout(conn, row)
    if cutout is not None:
        # One enrichment wake signal → the orchestrator tags + embeds (§11.4).
        await enqueue_signal(KIND_ENRICHMENT, str(row["id"]), provider=provider)


async def run_once(
    conn: asyncpg.Connection, provider: QueueProvider, *, stale_seconds: int, max_attempts: int
) -> int:
    queue = get_settings().azure_queue_jobs
    signals = await provider.receive_signals(
        queue, max_messages=_BATCH, visibility_timeout=_VISIBILITY
    )
    for sig in signals:
        await handle_signal(
            conn, provider, sig, queue, stale_seconds=stale_seconds, max_attempts=max_attempts
        )
    return len(signals)


async def _run_forever() -> None:
    s = get_settings()
    has_db = await init_db()
    provider = get_queue_provider()
    if not has_db:
        log.warning("CONNECTION_STRING not set — rembg worker has no DB; staying idle.")
    try:
        # Fail before claiming any row if the model can't load (§ BG upgrade §8).
        prewarm_background_remover()
        while True:
            n = 0
            if has_db:
                async with get_pool().acquire() as conn:
                    n = await run_once(
                        conn,
                        provider,
                        stale_seconds=s.worker_stale_seconds,
                        max_attempts=s.worker_max_attempts,
                    )
            await asyncio.sleep(0 if n else POLL_INTERVAL_SECONDS)
    finally:
        await provider.close()
        await close_db()


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    init_sentry()
    log.info("Fashion OS rembg worker started (cutout critical path).")
    asyncio.run(_run_forever())


if __name__ == "__main__":
    main()
