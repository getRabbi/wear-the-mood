"""News ingestion cron (CLAUDE.md §1 pillar 5). Run with ``python -m app.cron.news``.

Two paths, and which one runs is data, not configuration drift:

* **Source-driven** (the production path). When `feature_news_automation` is ON
  and `news_sources` holds enabled rows, each source is ingested independently
  with its own run row, backoff and lifecycle. A dead feed fails alone.

* **Legacy env-driven** (what this cron has always done). When automation is off
  or no sources are configured, it falls back to the original
  `fetch -> summarize -> upsert` over `NEWS_RSS_FEEDS`. Nothing that worked
  before stops working, which is why the old `ingest()` is still here and still
  exercised by its tests.

The flag is checked SERVER-SIDE, so turning news automation off in the admin
console actually stops ingestion rather than only hiding a button.
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, get_pool, init_db
from app.core.flags import flag_enabled
from app.core.observability import init_sentry
from app.services.news import get_news_fetcher, get_news_summarizer, ingest
from app.services.news.pipeline import run_enabled_sources

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron")


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping news ingest.")
        return
    try:
        async with get_pool().acquire() as conn:
            automation_on = await flag_enabled(conn, "feature_news_automation", default=False)
            configured = 0
            if automation_on:
                configured = int(
                    await conn.fetchval("select count(*) from public.news_sources where enabled")
                    or 0
                )

            if automation_on and configured:
                summarizer = get_news_summarizer()

                # Admin "Sync Now" requests first — a human waiting on a button
                # outranks the schedule. Claiming is a conditional UPDATE, so
                # two workers cannot take the same request.
                while True:
                    claimed = await conn.fetchrow("select * from public.claim_queued_news_sync()")
                    if claimed is None:
                        break
                    try:
                        await run_enabled_sources(
                            conn,
                            summarizer,
                            trigger_source="admin",
                            triggered_by=claimed["triggered_by"],
                            dry_run=bool(claimed["dry_run"]),
                            source_id=str(claimed["source_id"]) if claimed["source_id"] else None,
                        )
                    except Exception:  # noqa: BLE001 - one request must not stop the rest
                        log.exception("unhandled error on requested news sync")
                    finally:
                        # ingest_source opens its own run rows; this placeholder
                        # is resolved either way so a request never looks stuck.
                        await conn.execute(
                            """
                            update public.news_sync_runs
                               set status = case when status = 'running'
                                                 then 'success' else status end,
                                   finished_at = coalesce(finished_at, now())
                             where id = $1
                            """,
                            claimed["run_id"],
                        )

                totals = await run_enabled_sources(conn, summarizer)
                log.info("news ingest (source-driven): %s", totals)
                return

            if automation_on:
                log.info("news automation is on but no sources are enabled — nothing to do.")
                return

            # Legacy path, unchanged.
            await ingest(conn, get_news_fetcher(), get_news_summarizer())
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS news cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
