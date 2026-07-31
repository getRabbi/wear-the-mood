"""Push-outbox backstop cron (CLAUDE.md §20). Run with:
``python -m app.cron.push_outbox``

The worker drains `notification_outbox` every couple of seconds, so in normal
operation this finds nothing. It exists for the case the worker is down, wedged
or mid-redeploy: push intents would otherwise sit undelivered until it came back.

Safe to run alongside the worker — both claim with FOR UPDATE SKIP LOCKED, so a
row is never sent twice, and both honour the same attempt cap.
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, init_db
from app.core.observability import init_sentry
from app.services.notifications import drain_notification_outbox

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.push_outbox")

#: One pass drains at most this many, in batches, so a large backlog after an
#: outage clears in one run rather than trickling out over several hours.
_BATCH = 50
_MAX_BATCHES = 20


async def main() -> None:
    init_sentry()
    if not await init_db():
        log.warning("CONNECTION_STRING not set — nothing to drain.")
        return
    try:
        total = 0
        for _ in range(_MAX_BATCHES):
            sent = await drain_notification_outbox(limit=_BATCH)
            total += sent
            if sent < _BATCH:
                break  # caught up
        log.info("push outbox backstop delivered %d intent(s)", total)
    finally:
        # Give the fire-and-forget delivery tasks a moment to finish before the
        # pool closes underneath them; without this a short backlog can be
        # cancelled mid-send and retried unnecessarily on the next run.
        await asyncio.sleep(0)
        await close_db()


if __name__ == "__main__":
    asyncio.run(main())
