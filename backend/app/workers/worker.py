"""Async job worker (Render `worker` service).

Polls the DB queue for try-on jobs and processes them (CLAUDE.md §7).
Run with: ``python -m app.workers.worker``
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.workers.ai_jobs_worker import run_once as ai_jobs_run_once
from app.workers.bg_worker import requeue_stale
from app.workers.bg_worker import run_once as bg_run_once
from app.workers.tryon_worker import run_once as tryon_run_once

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.worker")

# Idle poll cadence. Kept short so a freshly-added wardrobe item / try-on job is
# claimed within ~2s of being queued (BUG 1 — perceived latency). The loop still
# drains back-to-back (sleep 0) while there's work, so this only governs idle.
POLL_INTERVAL_SECONDS = 2


async def _run_forever() -> None:
    has_db = await init_db()
    if not has_db:
        log.warning("CONNECTION_STRING not set — worker has no DB; staying idle.")
    try:
        while True:
            worked = False
            if has_db:
                async with get_pool().acquire() as conn:
                    # Recover items abandoned by a previously-crashed worker.
                    await requeue_stale(conn)
                    # Drain all queues; any doing work keeps us off the backoff.
                    tryon_worked = await tryon_run_once(conn)
                    bg_worked = await bg_run_once(conn)
                    ai_worked = await ai_jobs_run_once(conn)
                    worked = tryon_worked or bg_worked or ai_worked
            # Drain back-to-back when busy; back off to polling when the queue is empty.
            await asyncio.sleep(0 if worked else POLL_INTERVAL_SECONDS)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS worker started (try-on + background removal + AI Studio).")
    asyncio.run(_run_forever())


if __name__ == "__main__":
    main()
