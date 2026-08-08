"""New-offer notification cron (CLAUDE.md §18, §20). Run with:
``python -m app.cron.offers``

Offers are admin-curated rows in `public.offers`; nothing in the product notified
anyone when one went live, so "new offer items" simply never reached users.

WHO GETS THEM. An offer is marketing, and there is no per-offer audience or
subscription model in the schema — so this deliberately does NOT broadcast. It
uses the targeting rule the product already has: the `promotional` preference
category, which is the one category that defaults **OFF** and is strictly opt-in
(migration 0043). Only users who explicitly turned promotional notifications on
are notified. Adding a real audience/topic model later means changing the
recipient query here and nothing else.

IDEMPOTENCY. Each (user, offer) notification carries `dedupe_key = offer:<id>`, so
re-running the cron — on a retry, an overlapping schedule, or a redeploy — cannot
send the same offer twice. That makes the whole job safely restartable.
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.notifications import create_notification

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.offers")

# Offers that went live recently and are still in their validity window. The
# lookback only bounds the scan — `dedupe_key` is what prevents a repeat, so a
# late or re-run job still behaves correctly.
_LOOKBACK_HOURS = 48

_NEW_OFFERS_SQL = """
    select id, title, brand, discount_label
      from public.offers
     where is_active
       and created_at >= now() - make_interval(hours => $1)
       and (valid_from is null or valid_from <= now())
       and (valid_to   is null or valid_to   >= now())
     order by created_at
"""

# Strictly opt-in: only users who turned the promotional category ON. A missing
# preferences row means the DEFAULT, which for `promotional` is OFF — so absence
# is treated as "no", never as consent.
_OPTED_IN_SQL = """
    select np.user_id
      from public.notification_preferences np
      join public.profiles pr on pr.id = np.user_id
     where np.promotional is true
       and pr.account_status = 'active'
"""


async def notify_new_offers(conn: asyncpg.Connection) -> int:
    """Notify opted-in users about offers published in the lookback window.
    Returns the number of notifications actually created."""
    offers = await conn.fetch(_NEW_OFFERS_SQL, _LOOKBACK_HOURS)
    if not offers:
        log.info("no new offers in the last %dh", _LOOKBACK_HOURS)
        return 0

    recipients = [str(r["user_id"]) for r in await conn.fetch(_OPTED_IN_SQL)]
    if not recipients:
        log.info("%d new offer(s) but nobody has opted into promotional", len(offers))
        return 0

    created = 0
    for offer in offers:
        offer_id = str(offer["id"])
        brand = (offer["brand"] or "").strip()
        title = f"New from {brand}" if brand else "New offer"
        body = " · ".join(p for p in [offer["title"], offer["discount_label"]] if p)
        for user_id in recipients:
            outcome = await create_notification(
                conn,
                user_id=user_id,
                type="offer",
                title=title,
                body=body[:140] or None,
                target_type="offer",
                target_id=offer_id,
                dedupe_key=f"offer:{offer_id}",
                data={"offer_id": offer_id},
            )
            if outcome.created:
                created += 1
    log.info(
        "offers cron: %d offer(s) x %d opted-in user(s) -> %d new notification(s)",
        len(offers),
        len(recipients),
        created,
    )
    return created


async def main() -> None:
    init_sentry()
    await init_db()
    try:
        async with get_pool().acquire() as conn:
            await notify_new_offers(conn)
    finally:
        await close_db()


if __name__ == "__main__":
    asyncio.run(main())
