"""AI-spend alert cron (CLAUDE.md §14 — cost runaway is risk #1).

Sums the last 24h of ``ai_usage_log.estimated_usd`` and ALERTS (log.error + Sentry)
when it reaches ``DAILY_COST_ALERT_USD``, so a spend spike is caught fast — the
admin then flips the ``ai_tryon_enabled`` kill-switch to stop it. Run with
``python -m app.cron.spend_alert``.
"""

from __future__ import annotations

import asyncio
import logging

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.spend_alert")


async def _spend_last_24h(conn) -> float:
    val = await conn.fetchval(
        "select coalesce(sum(estimated_usd), 0) from public.ai_usage_log "
        "where created_at >= now() - interval '24 hours'"
    )
    return float(val or 0)


def _alert(spend: float, threshold: float) -> None:
    msg = f"AI spend (24h) ${spend:.2f} >= alert threshold ${threshold:.2f}"
    log.error(msg)
    try:
        import sentry_sdk

        sentry_sdk.capture_message(msg, level="error")
    except Exception:  # pragma: no cover - Sentry optional
        pass


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping spend alert.")
        return
    try:
        threshold = get_settings().daily_cost_alert_usd
        async with get_pool().acquire() as conn:
            spend = await _spend_last_24h(conn)
        if threshold > 0 and spend >= threshold:
            _alert(spend, threshold)
        else:
            log.info("AI spend (24h): $%.2f (threshold $%.2f)", spend, threshold)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS spend-alert cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
