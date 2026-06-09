"""Async job worker (Render `worker` service).

Polls the DB queue for try-on jobs and processes them (CLAUDE.md §7).
Run with: ``python -m app.workers.worker``
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.workers.tryon_worker import run_once

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.worker")

POLL_INTERVAL_SECONDS = 5


async def _run_forever() -> None:
    has_db = await init_db()
    if not has_db:
        log.warning("CONNECTION_STRING not set — worker has no DB; staying idle.")
    try:
        while True:
            worked = False
            if has_db:
                async with get_pool().acquire() as conn:
                    worked = await run_once(conn)
            # Drain back-to-back when busy; back off to polling when the queue is empty.
            await asyncio.sleep(0 if worked else POLL_INTERVAL_SECONDS)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS try-on worker started.")
    asyncio.run(_run_forever())


if __name__ == "__main__":
    main()
