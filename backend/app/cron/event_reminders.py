"""Event reminders (RETENTION spec §15, §23).

Run hourly alongside the daily stylist push. Sends at most THREE reminders per
saved event — seven days out, two days out, and on the day — and only for events
whose owner explicitly opted that event in.

Three rules make this a reminder rather than a marketing channel:

  * **Opt-in is per event, not per account.** `style_events.reminder_opt_in`
    defaults false, so saving something to remember never signs the user up for
    push (§23).
  * **Each stage fires once, ever.** `reminders_sent` is appended to in the SAME
    statement that selects the event, so a re-run — or two workers — cannot send
    the seven-day nudge twice.
  * **It stops.** After the same-day reminder there is nothing left to send.
    There is no "you didn't open it" follow-up, because that is the guilt
    messaging §23 rules out.

The notification itself goes through `create_notification`, so it lands in the
in-app inbox and honours the user's `daily_style` push preference exactly like
every other message. This cron never talks to FCM directly.
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.db import close_db, get_pool, init_db
from app.core.flags import flag_enabled
from app.core.observability import init_sentry
from app.services.notifications import create_notification

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron.events")

#: (stage key, window opens, window closes) — the three moments worth a nudge.
#: Each window is a DAY wide so an hourly cron cannot miss one, and the
#: `reminders_sent` guard means a wide window still sends exactly once.
_STAGES = (
    ("d7", "6 days", "7 days"),
    ("d2", "1 day", "2 days"),
    ("d0", "0 days", "1 day"),
)

_COPY = {
    "d7": ("{name} is a week away", "Time to decide what you're wearing."),
    "d2": ("{name} is in two days", "Your saved look is ready when you are."),
    "d0": ("{name} is today", "Here's the look you picked."),
}

#: Claim-and-mark in one statement. `not (stage = any(reminders_sent))` is the
#: idempotency guard and the UPDATE ... RETURNING is the claim, so two workers
#: running the same hour cannot both take the same event.
_CLAIM = """
    update public.style_events
       set reminders_sent = array_append(reminders_sent, $1::text),
           updated_at = now()
     where id in (
       select id from public.style_events
        where reminder_opt_in
          and not (reminders_sent @> array[$1::text])
          and event_at >  now() + $2::interval
          and event_at <= now() + $3::interval
        order by event_at
        limit 200
        for update skip locked
     )
    returning id, user_id, name, event_at
"""


async def run_event_reminders(conn: asyncpg.Connection) -> int:
    """Send every reminder due right now. Returns how many were queued."""
    if not await flag_enabled(conn, "feature_event_planner", default=False):
        return 0

    queued = 0
    for stage, opens, closes in _STAGES:
        async with conn.transaction():
            rows = await conn.fetch(_CLAIM, stage, opens, closes)
            title_tpl, body = _COPY[stage]
            for row in rows:
                await create_notification(
                    conn,
                    user_id=str(row["user_id"]),
                    type="daily_style",
                    # The event's own name, which the user typed. Truncated so a
                    # pasted paragraph cannot become a lock-screen wall.
                    title=title_tpl.format(name=str(row["name"])[:60]),
                    body=body,
                    target_type="event",
                    target_id=str(row["id"]),
                    # Belt and braces alongside `reminders_sent`: even a
                    # hand-reset array cannot produce a duplicate message.
                    dedupe_key=f"style_event:{row['id']}:{stage}",
                    data={"route": "/wtm/plan/events", "event_id": str(row["id"])},
                )
                queued += 1
    if queued:
        log.info("event reminders: queued %d", queued)
    return queued


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping event reminders.")
        return
    try:
        async with get_pool().acquire() as conn:
            await run_event_reminders(conn)
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS event-reminder cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
