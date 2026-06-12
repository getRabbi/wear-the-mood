"""News ingestion cron (Render `cron` service, CLAUDE.md §1 pillar 5).

Run a few times a day. Fetches the configured sources (stub until the founder
picks RSS feeds), summarizes each article (Claude Haiku when a key is set, §2.1),
and upserts into news_items for the /v1/news feed. Run with:
``python -m app.cron.news``
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.news import get_news_fetcher, get_news_summarizer, ingest

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron")


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping news ingest.")
        return
    try:
        async with get_pool().acquire() as conn:
            await ingest(conn, get_news_fetcher(), get_news_summarizer())
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS news cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
