"""Monthly credit reset / no-rollover backstop (CLAUDE.md §18).

The RevenueCat RENEWAL webhook grants each new period's credits (SET plan balance
— no rollover). This cron is a DAILY safety net: for every active subscription it
ensures the CURRENT period has been granted, using the SAME per-period ref
(billing.grant_ref) so it's a no-op when the webhook already granted, and catches
any missed webhook. Top-up credits are never touched. Run with
``python -m app.cron.credit_reset``.
"""

from __future__ import annotations

import asyncio
import logging

from app.core.credits import grant_credits
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.billing import grant_ref

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.credit_reset")


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping credit reset.")
        return
    try:
        granted = 0
        async with get_pool().acquire() as conn:
            rows = await conn.fetch(
                "select s.user_id, s.current_period_start, p.monthly_credits "
                "from public.user_subscriptions s "
                "join public.plans p on p.tier = s.tier "
                "where s.status = 'active' and p.monthly_credits > 0 "
                "and s.current_period_start is not null "
                "and (s.current_period_end is null or s.current_period_end > now())"
            )
            for r in rows:
                applied = await grant_credits(
                    conn,
                    str(r["user_id"]),
                    amount=r["monthly_credits"],
                    reason="grant",
                    ref=grant_ref(str(r["user_id"]), r["current_period_start"]),
                    set_plan_balance=True,
                    target="plan",
                )
                if applied:
                    granted += 1
        log.info("credit reset: granted %d subscription(s) for the current period", granted)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS credit-reset cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
