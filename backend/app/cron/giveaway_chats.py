"""Giveaway pickup-chat retention cron (0037, CLAUDE.md §10/§19).

Enforces the secret-pickup-chat retention policy on a schedule (hourly via
ofelia — see docker-compose.yml):

  1. EXPIRE  — active chats past ``approved_at + 7 days`` lock (`expired`);
               their accepted request is marked `expired` and the listing goes
               back to `available` so the owner can pick someone else.
  2. NUDGE   — active chats inside their last 24h get a one-time
               "expiring soon" in-app notification to both participants.
  3. REDACT  — message BODIES of ended chats (expired/completed/cancelled/
               locked) are deleted; only row metadata stays. REPORTED chats are
               skipped — a transcript under moderation review is never wiped.
  4. PURGE   — declined / not-selected requests are deleted 72h after settling.

Every step is idempotent — a re-run (or two racing runs) converges on the same
state. Run with ``python -m app.cron.giveaway_chats``.
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.notifications import create_notification

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.giveaway_chats")


async def expire_chats(conn: asyncpg.Connection) -> int:
    """Lock every active chat past its 7-day window, then settle the fallout of
    ANY expired chat that hasn't been settled yet: its accepted request becomes
    `expired` and the still-reserved listing goes back up. The settle step keys
    off the chat's `expired` STATE (not this run's transitions) because the API
    also flips chats lazily at read time — those must not slip through.
    Idempotent throughout."""
    rows = await conn.fetch(
        """
        update public.giveaway_pickup_chats
           set status = 'expired', locked_at = coalesce(locked_at, now()),
               updated_at = now()
         where status = 'active' and now() >= expires_at
        returning id
        """
    )
    await conn.execute(
        """
        update public.giveaway_claims cl
           set status = 'expired', updated_at = now()
          from public.giveaway_pickup_chats pc
         where pc.claim_id = cl.id and pc.status = 'expired'
           and cl.status = 'accepted'
        """
    )
    # Reopen listings whose pickup timed out — unless a newer chat is live
    # (the owner already re-accepted someone else).
    await conn.execute(
        """
        update public.giveaways g
           set status = 'available', updated_at = now()
          from public.giveaway_pickup_chats pc
         where pc.giveaway_id = g.id and pc.status = 'expired'
           and g.status = 'reserved'
           and not exists (
             select 1 from public.giveaway_pickup_chats live
              where live.giveaway_id = g.id and live.status = 'active'
           )
        """
    )
    return len(rows)


async def notify_expiring(conn: asyncpg.Connection) -> int:
    """One-time "expires in <24h" nudge to both participants of a still-active
    chat. `expiry_notified` makes it fire exactly once per chat window."""
    rows = await conn.fetch(
        """
        update public.giveaway_pickup_chats
           set expiry_notified = true, updated_at = now()
         where status = 'active' and expiry_notified = false
           and expires_at > now() and expires_at <= now() + interval '24 hours'
        returning giveaway_id, owner_id, requester_id
        """
    )
    for r in rows:
        for uid in (str(r["owner_id"]), str(r["requester_id"])):
            await create_notification(
                conn,
                user_id=uid,
                type="giveaway",
                title="Pickup chat expires soon",
                body="Less than a day left to arrange the pickup.",
                target_type="giveaway",
                target_id=str(r["giveaway_id"]),
            )
    return len(rows)


async def redact_ended_chats(conn: asyncpg.Connection) -> int:
    """Delete message bodies of ended chats, keeping metadata only (§10).
    Reported chats are frozen for moderation review — never redacted here
    until the flag is cleared. Idempotent via `body_deleted = false`."""
    result = await conn.execute(
        """
        update public.giveaway_chat_messages m
           set body = null, body_deleted = true, deleted_at = now()
          from public.giveaway_pickup_chats c
         where m.chat_id = c.id and m.body_deleted = false
           and c.report_flag = false
           and c.status in ('expired','completed','cancelled','locked')
        """
    )
    return int(result.split()[-1]) if result else 0


async def purge_settled_claims(conn: asyncpg.Connection) -> int:
    """Drop declined / not-selected requests 72h after they settled — no reason
    to keep who-asked-for-what around longer (§10). Chats reference claims with
    ON DELETE SET NULL, so history rows stay coherent."""
    result = await conn.execute(
        "delete from public.giveaway_claims "
        "where status in ('declined','not_selected') "
        "and updated_at < now() - interval '72 hours'"
    )
    return int(result.split()[-1]) if result else 0


async def run_cleanup(conn: asyncpg.Connection) -> dict[str, int]:
    counts = {
        "expired": await expire_chats(conn),
        "notified": await notify_expiring(conn),
        "redacted": await redact_ended_chats(conn),
        "purged": await purge_settled_claims(conn),
    }
    log.info(
        "giveaway chat cleanup: %d expired, %d nudged, %d messages redacted, "
        "%d stale requests purged.",
        counts["expired"],
        counts["notified"],
        counts["redacted"],
        counts["purged"],
    )
    return counts


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping giveaway chat cleanup.")
        return
    try:
        async with get_pool().acquire() as conn:
            await run_cleanup(conn)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS giveaway pickup-chat cleanup cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
