"""AI orchestrator entrypoint (Azure Container App ``wtm-ai-orchestrator``, §11.4).

Wakes on the ``enrichment`` queue and drains three surfaces by signal kind:

  * ``tryon``      → ``tryon_jobs``  (FASHN try-on — reuses ``tryon_worker.process_job``)
  * ``ai``         → ``ai_jobs``     (enhance / catalog — reuses ``ai_jobs_worker.process_ai_job``)
  * ``enrichment`` → wardrobe tagging + embedding (reuses ``bg_worker.process_enrichment``)

Owns terminal state, credit deduction/refund and poison handling. Safe under
duplicate wake signals and replica termination: claims are ``skip locked`` +
lease-based, and the credit spend/refund helpers are idempotent on the job id.

Run with: ``python -m app.workers.ai_orchestrator``
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.queues import KIND_AI, KIND_ENRICHMENT, KIND_TRYON, get_queue_provider
from app.queues.base import QueueProvider, ReceivedSignal
from app.services.imagegen import get_image_enhancer
from app.services.media.repo import resolve_images
from app.services.storage import download_image
from app.services.tryon import get_tryon_provider
from app.workers import ai_jobs_worker, tryon_worker
from app.workers.bg_worker import process_enrichment
from app.workers.claim import claim_ai_job, claim_tryon_job

log = logging.getLogger("fashionos.worker.orchestrator")

POLL_INTERVAL_SECONDS = 2
_VISIBILITY = 600  # try-on / FASHN can take a while; keep the signal hidden longer
_BATCH = 8

_TRYON_POISON_MSG = (
    "We couldn't generate your try-on. Please try again — your credits were refunded."
)
_AI_POISON_MSG = "We couldn't finish that. Please try again — your credit was refunded."


async def _enrich(conn: asyncpg.Connection, item_id: object) -> None:
    """Re-fetch the item's cutout and run best-effort tagging + embedding (idempotent)."""
    item = await conn.fetchrow(
        "select id, user_id, title, category, cutout_url, image_url "
        "from public.wardrobe_items where id = $1::uuid",
        str(item_id),
    )
    if item is None:
        return
    assets = await resolve_images(conn, "wardrobe_item", [str(item_id)], ("cutout",))
    hit = assets.get((str(item_id), "cutout"))
    url = hit.url if (hit and hit.url) else item["cutout_url"]
    if not url:
        return
    cutout = await download_image(url)
    await process_enrichment(conn, item, cutout)


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
    if msg is None:
        await provider.delete_signal(queue, signal)
        return

    if msg.kind == KIND_TRYON:
        row = await claim_tryon_job(conn, msg.job_id, stale_seconds=stale_seconds)
        await provider.delete_signal(queue, signal)
        if row is None:
            return
        if row["attempt_count"] > max_attempts:
            await tryon_worker._fail_and_refund(
                conn,
                job_id=row["id"],
                user_id=row["user_id"],
                error=_TRYON_POISON_MSG,
                provider=get_tryon_provider().name,
                latency_ms=0,
                images=1,
            )
            log.error("tryon poison job=%s attempts=%s", row["id"], row["attempt_count"])
            return
        await tryon_worker.process_job(conn, row)

    elif msg.kind == KIND_AI:
        row = await claim_ai_job(conn, msg.job_id, stale_seconds=stale_seconds)
        await provider.delete_signal(queue, signal)
        if row is None:
            return
        if row["attempt_count"] > max_attempts:
            prov = (
                get_tryon_provider().name
                if row["job_type"] == "catalog_model"
                else get_image_enhancer().name
            )
            await ai_jobs_worker._fail_and_refund(
                conn, job=row, error=_AI_POISON_MSG, provider=prov, latency_ms=0
            )
            log.error("ai poison job=%s attempts=%s", row["id"], row["attempt_count"])
            return
        await ai_jobs_worker.process_ai_job(conn, row)

    elif msg.kind == KIND_ENRICHMENT:
        await provider.delete_signal(queue, signal)
        try:
            await _enrich(conn, msg.job_id)
        except Exception as exc:  # noqa: BLE001 - enrichment is best-effort
            log.warning("enrichment for item %s failed: %s", msg.job_id, exc)

    else:  # unknown kind on this queue → drop
        await provider.delete_signal(queue, signal)


async def run_once(
    conn: asyncpg.Connection, provider: QueueProvider, *, stale_seconds: int, max_attempts: int
) -> int:
    queue = get_settings().azure_queue_enrichment
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
        log.warning("CONNECTION_STRING not set — orchestrator has no DB; staying idle.")
    try:
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
    log.info("Fashion OS AI orchestrator started (try-on + AI Studio + enrichment).")
    asyncio.run(_run_forever())


if __name__ == "__main__":
    main()
