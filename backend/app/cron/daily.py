"""Daily stylist push (Render `cron` service, CLAUDE.md §20).

Run hourly. Each run delivers the morning nudge to every device whose *local*
time is the configured push hour, so users get it at their own breakfast — never
a single 3am-UTC blast. The push is a lightweight teaser that deep-links to the
stylist screen; the actual outfit is generated on-demand when they tap, so we
don't run an LLM for every user at cron time (cost control, §14).

Delivery goes through the resolved PushSender (stub by default; FCM once the
founder's Firebase creds are set). Run with: ``python -m app.cron.daily``
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.config import get_settings
from app.core.db import close_db, get_pool, init_db
from app.core.observability import init_sentry
from app.services.push import DeliveryStatus, PushMessage, PushSender, get_push_sender

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("fashionos.cron")

# Devices whose local hour matches the target, opted in (master push_opt_in),
# still valid (not invalidated) AND who haven't muted the 'daily_style' push
# category (§20). UTC for unknown tz. A missing preferences row means the default
# (daily_style ON).
_DUE_TOKENS = """
    select dt.token, dt.user_id
      from public.device_tokens dt
      join public.profiles p on p.id = dt.user_id
      left join public.notification_preferences np on np.user_id = dt.user_id
     where dt.push_opt_in
       and dt.invalidated_at is null
       and coalesce(np.daily_style, true)
       and extract(hour from (now() at time zone coalesce(p.timezone, 'UTC'))) = $1
"""


def _daily_message() -> PushMessage:
    return PushMessage(
        title="Today's outfit is ready 👗",
        body="Tap to see what to wear today.",
        data={"route": "/stylist"},
    )


async def run_daily_push(conn: asyncpg.Connection, sender: PushSender, *, target_hour: int) -> int:
    """Send the morning nudge to every device currently at local `target_hour`.
    Returns the number of pushes delivered. Per-token failures are swallowed by
    the sender so one bad token can't stop the run."""
    rows = await conn.fetch(_DUE_TOKENS, target_hour)
    message = _daily_message()
    sent = 0
    dead: list[str] = []
    for row in rows:
        status = await sender.send(row["token"], message)
        if status == DeliveryStatus.ok:
            sent += 1
        elif status == DeliveryStatus.invalid_token:
            dead.append(row["token"])  # permanently gone → deactivate below
        elif status == DeliveryStatus.auth_error:
            log.error("daily push aborted: sender credential/config error")
            break  # same for every token — don't storm FCM
    if dead:
        # Never delete — only mark inactive so history + re-registration survive (§6).
        await conn.execute(
            "update public.device_tokens set invalidated_at = now() "
            "where token = any($1::text[]) and invalidated_at is null",
            dead,
        )
    log.info(
        "daily push: %d/%d devices via %s (%d pruned)",
        sent,
        len(rows),
        sender.name,
        len(dead),
    )
    return sent


async def _run() -> None:
    if not await init_db():
        log.warning("CONNECTION_STRING not set — skipping daily push.")
        return
    try:
        async with get_pool().acquire() as conn:
            await run_daily_push(
                conn, get_push_sender(), target_hour=get_settings().daily_push_hour
            )
    finally:
        await close_db()


def main() -> None:
    init_sentry()
    log.info("Fashion OS daily cron starting.")
    asyncio.run(_run())


if __name__ == "__main__":
    main()
