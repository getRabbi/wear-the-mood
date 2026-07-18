"""Stale / lost-signal recovery (Azure scheduled Job ``wtm-recovery``, every 5 min; §11.6).

Finds non-terminal job rows whose lease is stale, re-emits **duplicate-safe** wake
signals, and terminates poison rows exactly once (fail + idempotent refund). It NEVER
queries Azure Queue for a matching message (§4.2) — it re-signals from the DB, and
duplicate signals are harmless because claims + refunds are idempotent. Logs counts
only (no secrets). One-shot: exits 0 on success, non-zero on error, no internal loop.

Run with: ``python -m app.tasks.recovery``
"""

from __future__ import annotations

import asyncio
import logging
import sys

import asyncpg

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.queues import KIND_AI, KIND_REMBG, KIND_TRYON, enqueue_signal, get_queue_provider
from app.queues.base import QueueProvider
from app.services.imagegen import get_image_enhancer
from app.services.tryon import get_tryon_provider
from app.workers import ai_jobs_worker, tryon_worker

log = logging.getLogger("fashionos.tasks.recovery")

_STALE_TRYON = """
select id, user_id, attempt_count from public.tryon_jobs
 where status = 'processing'
   and (locked_at is null or locked_at < now() - make_interval(secs => $1::int))
"""
_STALE_AI = """
select id, user_id, job_type, source_item_id, attempt_count from public.ai_jobs
 where status = 'processing'
   and (locked_at is null or locked_at < now() - make_interval(secs => $1::int))
"""
_STALE_CUTOUT = """
select id, attempt_count from public.wardrobe_items
 where cutout_status = 'processing'
   and updated_at < now() - make_interval(secs => $1::int)
"""

_TRYON_POISON_MSG = (
    "We couldn't generate your try-on. Please try again — your credits were refunded."
)
_AI_POISON_MSG = "We couldn't finish that. Please try again — your credit was refunded."


async def _recover(
    conn: asyncpg.Connection, provider: QueueProvider, *, stale: int, max_attempts: int
) -> dict[str, int]:
    c = {
        "tryon_resignal": 0,
        "tryon_poison": 0,
        "ai_resignal": 0,
        "ai_poison": 0,
        "cutout_resignal": 0,
        "cutout_poison": 0,
    }

    for r in await conn.fetch(_STALE_TRYON, stale):
        if r["attempt_count"] >= max_attempts:
            await tryon_worker._fail_and_refund(
                conn,
                job_id=r["id"],
                user_id=r["user_id"],
                error=_TRYON_POISON_MSG,
                provider=get_tryon_provider().name,
                latency_ms=0,
                images=1,
            )
            c["tryon_poison"] += 1
        else:
            if await enqueue_signal(KIND_TRYON, str(r["id"]), provider=provider):
                await conn.execute(
                    "update public.tryon_jobs set last_signal_at = now() where id = $1::uuid",
                    str(r["id"]),
                )
            c["tryon_resignal"] += 1

    for r in await conn.fetch(_STALE_AI, stale):
        if r["attempt_count"] >= max_attempts:
            prov = (
                get_tryon_provider().name
                if r["job_type"] == "catalog_model"
                else get_image_enhancer().name
            )
            await ai_jobs_worker._fail_and_refund(
                conn, job=r, error=_AI_POISON_MSG, provider=prov, latency_ms=0
            )
            c["ai_poison"] += 1
        else:
            if await enqueue_signal(KIND_AI, str(r["id"]), provider=provider):
                await conn.execute(
                    "update public.ai_jobs set last_signal_at = now() where id = $1::uuid",
                    str(r["id"]),
                )
            c["ai_resignal"] += 1

    for r in await conn.fetch(_STALE_CUTOUT, stale):
        if r["attempt_count"] >= max_attempts:
            await conn.execute(
                "update public.wardrobe_items set cutout_status = 'failed', "
                "cutout_error_code = 'max_attempts' where id = $1::uuid",
                str(r["id"]),
            )
            c["cutout_poison"] += 1
        else:
            if await enqueue_signal(KIND_REMBG, str(r["id"]), provider=provider):
                await conn.execute(
                    "update public.wardrobe_items set cutout_last_signal_at = now() "
                    "where id = $1::uuid",
                    str(r["id"]),
                )
            c["cutout_resignal"] += 1

    return c


async def _run() -> int:
    s = get_settings()
    has_db = await init_db()
    if not has_db:
        log.warning("CONNECTION_STRING not set — recovery is a no-op.")
        return 0
    provider = get_queue_provider()
    try:
        async with get_pool().acquire() as conn:
            counts = await _recover(
                conn, provider, stale=s.worker_stale_seconds, max_attempts=s.worker_max_attempts
            )
        log.info("recovery complete: %s", counts)
        return 0
    finally:
        await provider.close()
        await close_db()


def main() -> int:
    logging.basicConfig(level=logging.INFO)
    init_sentry()
    return asyncio.run(_run())


if __name__ == "__main__":
    sys.exit(main())
