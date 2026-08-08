"""Merchant product ingestion cron. Run with ``python -m app.cron.product_sync``.

Walks every approved merchant that has an ENABLED feed and syncs it. Each
merchant is independent: one failing feed produces a failed run row and backoff
for that merchant, and the others still import. That isolation is the whole
reason this iterates rather than gathering.

Gated on `feature_product_automation`, which migration 0057 registers FALSE. The
gate is checked here, server-side, so switching automation off in the admin
console actually stops the importer rather than only hiding a button.
"""

from __future__ import annotations

import asyncio
import logging

from app.core.db import close_db, get_pool, init_db
from app.core.flags import flag_enabled
from app.core.observability import init_sentry
from app.services.catalog import sync_merchant

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.product_sync")

_DUE_MERCHANTS = """
    select c.merchant_id
      from public.merchant_feed_config c
      join public.merchants m on m.id = c.merchant_id
     where c.enabled and m.approved
       and (c.retry_after is null or c.retry_after <= now())
     order by c.updated_at asc
"""


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping product sync.")
        return
    try:
        async with get_pool().acquire() as conn:
            if not await flag_enabled(conn, "feature_product_automation", default=False):
                log.info("feature_product_automation is off — nothing to do.")
                return

            # Admin "Sync Now" requests first. They are queued run rows, and a
            # human waiting on a button outranks the schedule. Claiming is a
            # conditional UPDATE, so two workers cannot take the same request.
            while True:
                claimed = await conn.fetchrow("select * from public.claim_queued_product_sync()")
                if claimed is None:
                    break
                merchant_id = str(claimed["merchant_id"])
                try:
                    # `respect_interval=False`: an operator pressing the button
                    # is explicitly asking to bypass the schedule floor.
                    outcome = await sync_merchant(
                        conn,
                        merchant_id,
                        trigger_source="admin",
                        triggered_by=claimed["triggered_by"],
                        dry_run=bool(claimed["dry_run"]),
                        respect_interval=False,
                    )
                    log.info(
                        "admin sync %s -> %s %s",
                        merchant_id,
                        outcome.status,
                        outcome.counts.as_dict(),
                    )
                except Exception:  # noqa: BLE001 - one request must not stop the rest
                    log.exception("unhandled error on requested sync for %s", merchant_id)
                finally:
                    # The placeholder row is resolved either way: sync_merchant
                    # opens its own run, so leaving this one 'running' would
                    # show a request that never finished.
                    await conn.execute(
                        """
                        update public.product_sync_runs
                           set status = case when status = 'running' then 'success' else status end,
                               finished_at = coalesce(finished_at, now())
                         where id = $1
                        """,
                        claimed["run_id"],
                    )

            merchants = await conn.fetch(_DUE_MERCHANTS)
            log.info("product sync: %d merchant feed(s) due.", len(merchants))
            for row in merchants:
                merchant_id = str(row["merchant_id"])
                try:
                    outcome = await sync_merchant(conn, merchant_id, trigger_source="cron")
                    log.info(
                        "merchant %s -> %s %s",
                        merchant_id,
                        outcome.status,
                        outcome.counts.as_dict(),
                    )
                except Exception:  # noqa: BLE001 - one merchant must not stop the rest
                    log.exception("unhandled error syncing merchant %s", merchant_id)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS product sync cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
