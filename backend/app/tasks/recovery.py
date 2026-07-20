"""Stale / lost-signal recovery (Azure scheduled Job ``wtm-recovery``, every 5 min; §11.6).

Re-emits **duplicate-safe** wake signals for non-terminal job rows, and terminates
poison rows exactly once (fail + idempotent refund). It NEVER queries Azure Queue for a
matching message (§4.2) — it re-signals from the DB, and duplicate signals are harmless
because claims + refunds are idempotent. Logs counts only (no secrets). One-shot: exits
0 on success, non-zero on error, no internal loop.

Two distinct failure modes are healed, and both are required:

* **stale ``processing``** — a worker claimed the row and died mid-flight, so the lease
  (``locked_at`` for jobs, ``cutout_locked_at`` for cutouts) has aged past
  ``WORKER_STALE_SECONDS``. Both are written ONLY by the claim, never by a re-signal —
  see 0046: leasing cutouts on ``updated_at`` livelocked them, because the re-signal
  bumps ``updated_at`` through a trigger and so reset its own staleness clock.
* **stranded ``queued``** — the row committed but its wake signal never reached the
  queue, so no worker will ever be woken for it. ``enqueue_signal`` is deliberately
  best-effort and returns False on failure (§11.5); this scan is the backstop that its
  docstring promises. Detected via ``last_signal_at`` / ``cutout_last_signal_at``, which
  are stamped only when the enqueue actually succeeded — so a failed enqueue leaves NULL
  and is healed on the very next run.

Without the second scan a lost signal is unrecoverable: the batch workers wake **only**
from queue messages and never poll the DB for ``queued`` rows, so the row would sit
queued forever while the user waits. Rows written by the pre-migration DigitalOcean API
(which cannot enqueue to Azure at all) are exactly this case.

⚠ **Do not enable this job while the DigitalOcean worker is still running.** It would
re-signal DO-owned ``queued`` rows into Azure and put both worker planes on the same
row — the overlap hazard recorded in ``MIGRATION_STATE.md``. Enable it only after the DO
worker and ofelia are stopped.

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

# The `-- recovery:<name>` markers make each statement uniquely identifiable; several
# of these differ only by the state they filter on.
_STALE_TRYON = """
-- recovery:stale-tryon
select id, user_id, attempt_count from public.tryon_jobs
 where status = 'processing'
   and (locked_at is null or locked_at < now() - make_interval(secs => $1::int))
"""
_STALE_AI = """
-- recovery:stale-ai
select id, user_id, job_type, source_item_id, attempt_count from public.ai_jobs
 where status = 'processing'
   and (locked_at is null or locked_at < now() - make_interval(secs => $1::int))
"""
# Leases on `cutout_locked_at` (0046). Using `updated_at` here livelocked: the
# re-signal below bumps `updated_at` via trg_wardrobe_items_updated_at, resetting
# the very clock this scan tests, so an abandoned row was re-signalled forever and
# never re-claimable. `cutout_locked_at` is written only by the claim.
_STALE_CUTOUT = """
-- recovery:stale-cutout
select id, attempt_count from public.wardrobe_items
 where cutout_status = 'processing'
   and (cutout_locked_at is null
        or cutout_locked_at < now() - make_interval(secs => $1::int))
"""

# Committed but never successfully signalled — nothing will ever wake a worker for
# these. `last_signal_at IS NULL` means the enqueue failed (or the row predates the
# queue, e.g. written by the DO API), so it is healed on the next run rather than
# after the stale window.
_STRANDED_TRYON = """
-- recovery:stranded-tryon
select id, user_id, attempt_count from public.tryon_jobs
 where status = 'queued'
   and (last_signal_at is null
        or last_signal_at < now() - make_interval(secs => $1::int))
"""
_STRANDED_AI = """
-- recovery:stranded-ai
select id, user_id, job_type, source_item_id, attempt_count from public.ai_jobs
 where status = 'queued'
   and (last_signal_at is null
        or last_signal_at < now() - make_interval(secs => $1::int))
"""
_STRANDED_CUTOUT = """
-- recovery:stranded-cutout
select id, attempt_count from public.wardrobe_items
 where cutout_status = 'queued'
   and (cutout_last_signal_at is null
        or cutout_last_signal_at < now() - make_interval(secs => $1::int))
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
        "tryon_stranded": 0,
        "tryon_poison": 0,
        "ai_resignal": 0,
        "ai_stranded": 0,
        "ai_poison": 0,
        "cutout_resignal": 0,
        "cutout_stranded": 0,
        "cutout_poison": 0,
    }

    # Healing a stale `processing` row and a stranded `queued` row is the same action —
    # re-signal, or terminate once the attempt budget is spent. Only the counter differs,
    # so the two scans share one handler per job kind.

    async def _heal_tryon(rows: list, *, counter: str) -> None:
        for r in rows:
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
                c[counter] += 1

    async def _heal_ai(rows: list, *, counter: str) -> None:
        for r in rows:
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
                c[counter] += 1

    async def _heal_cutout(rows: list, *, counter: str) -> None:
        for r in rows:
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
                c[counter] += 1

    await _heal_tryon(await conn.fetch(_STALE_TRYON, stale), counter="tryon_resignal")
    await _heal_ai(await conn.fetch(_STALE_AI, stale), counter="ai_resignal")
    await _heal_cutout(await conn.fetch(_STALE_CUTOUT, stale), counter="cutout_resignal")

    await _heal_tryon(await conn.fetch(_STRANDED_TRYON, stale), counter="tryon_stranded")
    await _heal_ai(await conn.fetch(_STRANDED_AI, stale), counter="ai_stranded")
    await _heal_cutout(await conn.fetch(_STRANDED_CUTOUT, stale), counter="cutout_stranded")

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
