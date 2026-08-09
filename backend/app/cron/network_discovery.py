"""Affiliate network discovery cron. ``python -m app.cron.network_discovery``.

Deliberately SEPARATE from product sync, and much less frequent. Reading an
account's feed listing is one request that answers "what could we import"; a
product sync downloads catalogues. Tying them together would mean either
listing far too often or discovering far too rarely, and they have different
failure modes — a listing outage should not stop imports that are already
configured.

Gated on `feature_network_discovery`, checked server-side, so the admin switch
actually stops it rather than only hiding a button.
"""

from __future__ import annotations

import asyncio
import logging
import os

from app.core.db import close_db, get_pool, init_db
from app.core.flags import flag_enabled
from app.core.observability import init_sentry
from app.services.catalog.networks.discovery import discover_awin

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.network_discovery")

# The scheduler ticks often so that an admin pressing "Re-scan network" is picked
# up in minutes. An account's advertiser list does not change on that timescale,
# so listing on every tick would send the same request ~48 times a day and learn
# nothing 46 of them — which is how a partner API key earns a rate-limit or a
# revocation. The tick rate therefore governs ADMIN latency; this interval
# governs how often we actually talk to the network unprompted.
_DEFAULT_INTERVAL_HOURS = 12


def _scheduled_interval_hours() -> int:
    """Hours between unprompted listings. Env-tunable for cost/runbook changes."""
    raw = (os.getenv("NETWORK_DISCOVERY_INTERVAL_HOURS") or "").strip()
    if not raw:
        return _DEFAULT_INTERVAL_HOURS
    try:
        parsed = int(raw)
    except ValueError:
        log.warning("NETWORK_DISCOVERY_INTERVAL_HOURS=%r is not an integer — using default", raw)
        return _DEFAULT_INTERVAL_HOURS
    # 0 or negative would mean "list every tick", the exact cost failure this
    # gate exists to prevent, so it is not an available setting.
    return parsed if parsed > 0 else _DEFAULT_INTERVAL_HOURS


# Age is compared in the DATABASE, not in this process: the run rows are written
# with the database clock, so comparing them against a container's clock would
# make the gate depend on two clocks agreeing.
#
# Deliberately "the last attempt", not "the last success". A network that is
# failing is the case where retrying every 30 minutes does the most damage, and
# an operator who wants an immediate retry has the admin re-scan button — which
# bypasses this gate entirely because it is drained above.
_SCHEDULED_DISCOVERY_DUE = """
    select not exists (
        select 1
          from public.network_discovery_runs
         where network = $1
           and trigger_source = 'cron'
           and started_at > now() - make_interval(hours => $2)
    )
"""


async def _scheduled_discovery_due(conn, network: str) -> bool:
    hours = _scheduled_interval_hours()
    return bool(await conn.fetchval(_SCHEDULED_DISCOVERY_DUE, network, hours))


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping network discovery.")
        return
    try:
        async with get_pool().acquire() as conn:
            if not await flag_enabled(conn, "feature_network_discovery", default=False):
                log.info("feature_network_discovery is off — nothing to do.")
                return

            # Admin "Re-scan network" requests first, and the claimed row IS the
            # run — an operator watching a button press should see one run, not
            # a queued row plus an unrelated cron row that did the work.
            drained = 0
            while True:
                claimed = await conn.fetchrow(
                    "select * from public.claim_queued_network_discovery()"
                )
                if claimed is None:
                    break
                drained += 1
                if claimed["network"] != "awin":
                    # A network this build has no connector for. Close the row
                    # rather than leaving it 'running' forever, and say why.
                    await conn.execute(
                        """
                        update public.network_discovery_runs
                           set status = 'failed', error_message = $2,
                               finished_at = now()
                         where id = $1
                        """,
                        claimed["run_id"],
                        f"no connector for network '{claimed['network']}'",
                    )
                    log.warning(
                        "discovery requested for unsupported network %s", claimed["network"]
                    )
                    continue
                result = await discover_awin(
                    conn,
                    trigger_source="admin",
                    triggered_by=claimed["triggered_by"],
                    run_id=str(claimed["run_id"]),
                )
                log.info("requested awin discovery: %s", result)

            # A scheduled pass only when nobody asked for one this tick; back to
            # back listings of the same account tell you the same thing twice.
            if drained:
                return
            if not await _scheduled_discovery_due(conn, "awin"):
                log.info(
                    "awin discovery not due (last scheduled pass within %dh) — nothing to do.",
                    _scheduled_interval_hours(),
                )
                return
            result = await discover_awin(conn, trigger_source="cron")
            log.info("awin discovery: %s", result)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS network discovery cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
