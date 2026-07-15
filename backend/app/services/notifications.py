"""In-app notifications (CLAUDE.md §1 pillar 4).

A tiny best-effort helper the social/try-on flows call to drop a notification in
a user's feed. Inserts run as the service-role backend (RLS-bypassing); clients
can never forge a notification (insert has no RLS policy). Creation never raises
into the caller — a failed notification must not break the action that triggered
it (a like/comment/follow).
"""

from __future__ import annotations

import asyncio
import logging

import asyncpg

from app.core.db import get_pool
from app.services.display import public_display_name
from app.services.push import PushMessage, get_push_sender

log = logging.getLogger("fashionos.notifications")

# Keep references to in-flight background push tasks so they aren't GC'd mid-send.
_push_tasks: set[asyncio.Task] = set()

# Route each notification type to its Android channel (created natively in the
# app's MainActivity, §20). Referral + account/job events → wtm_account; social
# → wtm_social; community/giveaway → wtm_community; anything else → the manifest
# default (wtm_updates).
_ACCOUNT_TYPES = frozenset(
    {"referral_reward", "account", "billing", "catalog_model", "enhance_item"}
)
_SOCIAL_TYPES = frozenset({"follow", "like", "comment", "reply", "mention", "post", "user"})
_COMMUNITY_TYPES = frozenset({"giveaway", "giveaway_message", "challenge"})


def _channel_for_type(notification_type: str) -> str:
    if notification_type in _ACCOUNT_TYPES:
        return "wtm_account"
    if notification_type in _SOCIAL_TYPES:
        return "wtm_social"
    if notification_type in _COMMUNITY_TYPES:
        return "wtm_community"
    return "wtm_updates"


def _route_for_type(notification_type: str) -> str:
    """In-app deep-link route a tapped push opens (validated app-side, §20)."""
    if notification_type == "referral_reward":
        return "/wtm/referral"
    return "/wtm/inbox"  # the notification center — safe for any type


async def push_to_user(user_id: str, message: PushMessage) -> None:
    """Deliver a push to a user's opted-in devices via the resolved sender (FCM in
    prod; stub otherwise). Uses its OWN pool connection so it is fully decoupled
    from the caller's request/transaction — the durable notification is the source
    of truth; this is only the delivery channel. Best-effort: never raises, honors
    the per-device `push_opt_in` flag, and never logs a full token."""
    try:
        async with get_pool().acquire() as conn:
            rows = await conn.fetch(
                "select token from public.device_tokens "
                "where user_id = $1::uuid and push_opt_in",
                user_id,
            )
        if not rows:
            return
        sender = get_push_sender()
        delivered = 0
        for row in rows:
            if await sender.send(row["token"], message):
                delivered += 1
        log.info(
            "push '%s': %d/%d devices via %s",
            message.data.get("type", "?"),
            delivered,
            len(rows),
            sender.name,
        )
    except Exception as exc:  # delivery is best-effort — never surface
        log.warning("push to %s failed: %s", user_id, exc)


def deliver_push_async(user_id: str, message: PushMessage) -> None:
    """Fire-and-forget a best-effort push so it never blocks the caller's request
    or transaction (§20). No-op when there is no running event loop (e.g. sync
    scripts); keeps a task reference so it isn't GC'd before it completes."""
    try:
        task = asyncio.create_task(push_to_user(user_id, message))
    except RuntimeError:
        return  # no running loop
    _push_tasks.add(task)
    task.add_done_callback(_push_tasks.discard)


async def create_notification(
    conn: asyncpg.Connection,
    *,
    user_id: str,
    type: str,
    title: str,
    actor_id: str | None = None,
    body: str | None = None,
    target_type: str | None = None,
    target_id: str | None = None,
) -> None:
    """Insert a notification for [user_id]. Best-effort: never notify yourself,
    and swallow any error so the triggering action still succeeds."""
    if actor_id is not None and actor_id == user_id:
        return  # don't notify a user about their own action
    try:
        await conn.execute(
            """
            insert into public.notifications
              (user_id, actor_id, type, title, body, target_type, target_id)
            values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7)
            """,
            user_id,
            actor_id,
            type,
            title,
            body,
            target_type,
            target_id,
        )
    except Exception as exc:  # never break the caller's main action
        log.warning("notification insert failed for %s (%s): %s", user_id, type, exc)
        return  # durable record failed → nothing to deliver

    # Fire-and-forget push delivery (referral + social + all events). The durable
    # record above is the source of truth — this never blocks the caller's request
    # or transaction, and the in-app center works even when push is disabled.
    # Routed to the type's Android channel + a validated in-app deep link (§20).
    deliver_push_async(
        user_id,
        PushMessage(
            title=title,
            body=body or "",
            data={"type": type, "route": _route_for_type(type)},
            android_channel=_channel_for_type(type),
        ),
    )


async def actor_name(conn: asyncpg.Connection, actor_id: str) -> str:
    """Display name for an actor, for notification copy. Never an email — a raw
    email saved as the name must not leak into a notification title (§10).
    Falls back to the username, then 'Someone'."""
    row = await conn.fetchrow(
        "select display_name, username from public.profiles where id = $1::uuid",
        actor_id,
    )
    if row is None:
        return "Someone"
    return public_display_name(row["display_name"], row["username"]) or "Someone"
