"""Monthly community award cron (Render `cron` service, CLAUDE.md §1 pillar 4, §24).

Runs on the 1st of each month. Finds last month's Style-Score #1 and grants them a
free month of premium (a `promo` entitlement), records the win in community_awards
(idempotent via its unique month), and pushes them the good news. Run with:
``python -m app.cron.community``
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.billing import get_entitlement
from app.services.push import PushMessage, PushSender, get_push_sender

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.community")

# Last month's winner: highest Style-Score, ties broken by the earliest post.
# Score = likes*1 + comments*3 + 5/post, counting only OTHER users' engagement.
_WINNER_SQL = """
with post_scores as (
  select p.id, p.user_id, p.created_at,
         5
         + (select count(*) from public.likes l
              where l.post_id = p.id and l.user_id <> p.user_id)
         + 3 * (select count(*) from public.comments c
                  where c.post_id = p.id and c.user_id <> p.user_id) as score
    from public.posts p
   where p.created_at >= date_trunc('month', now()) - interval '1 month'
     and p.created_at <  date_trunc('month', now())
)
select user_id,
       sum(score)::int as score,
       (date_trunc('month', now()) - interval '1 month')::date as period_month
  from post_scores
 group by user_id
having sum(score) > 0
 order by sum(score) desc, min(created_at) asc
 limit 1
"""

_GRANT_SQL = """
insert into public.entitlements
  (user_id, active, product_id, store, expires_at, updated_at)
values ($1::uuid, true, 'community_reward', 'promo', now() + interval '30 days', now())
on conflict (user_id) do update set
  active = true,
  product_id = 'community_reward',
  store = 'promo',
  expires_at = now() + interval '30 days',
  updated_at = now()
"""


async def run_community_award(conn: asyncpg.Connection) -> str | None:
    """Grant last month's winner a free month. Returns the winner's id if newly
    awarded (so the caller can notify), else None. Idempotent per month."""
    row = await conn.fetchrow(_WINNER_SQL)
    if row is None:
        log.info("community award: no qualifying posts last month.")
        return None
    user_id, score, period_month = row["user_id"], row["score"], row["period_month"]

    awarded = await conn.fetchval(
        """
        insert into public.community_awards (user_id, period_month, score)
        values ($1::uuid, $2, $3)
        on conflict (period_month) do nothing
        returning id
        """,
        str(user_id),
        period_month,
        score,
    )
    if awarded is None:
        log.info("community award for %s already granted; skipping.", period_month)
        return None

    # Don't clobber an active paid subscription — only grant when not already premium.
    if not (await get_entitlement(conn, str(user_id))).active:
        await conn.execute(_GRANT_SQL, str(user_id))
    log.info(
        "community award: %s wins %s with score %d (premium granted).",
        user_id,
        period_month,
        score,
    )
    return str(user_id)


async def _notify_winner(conn: asyncpg.Connection, sender: PushSender, user_id: str) -> None:
    rows = await conn.fetch(
        "select token from public.device_tokens where user_id = $1::uuid and push_opt_in",
        user_id,
    )
    message = PushMessage(
        title="You won! 🏆",
        body="You topped the Style leaderboard — enjoy a free month of Premium!",
    )
    for r in rows:
        try:
            await sender.send(r["token"], message)
        except Exception:  # one bad token can't stop the run
            pass


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping community award.")
        return
    try:
        async with get_pool().acquire() as conn:
            winner = await run_community_award(conn)
            if winner is not None:
                await _notify_winner(conn, get_push_sender(), winner)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS community award cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
