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
from app.services.push import DeliveryStatus, PushMessage, get_push_sender

log = logging.getLogger("fashionos.notifications")

# Keep references to in-flight background push tasks so they aren't GC'd mid-send.
_push_tasks: set[asyncio.Task] = set()

# ── Canonical event → category → Android channel → route (CLAUDE.md §3/§20) ──
# One table drives everything: the PUSH preference category (gates delivery
# only), the native Android channel (created in MainActivity), and the in-app
# route a tap opens (validated app-side). A push is delivered only when BOTH the
# master device switch (push_opt_in) AND the category are enabled.

# Preference categories + their columns/defaults (notification_preferences,
# migration 0043). Everything defaults ON except `promotional` (strictly opt-in).
PREFERENCE_CATEGORIES = (
    "account_updates",
    "referral_rewards",
    "social_activity",
    "community",
    "daily_style",
    "product_updates",
    "promotional",
)

_CATEGORY_BY_TYPE: dict[str, str] = {
    # Referral rewards
    "referral_reward": "referral_rewards",
    # Account / billing / membership
    "payment_issue": "account_updates",
    "subscription_expired": "account_updates",
    "subscription_refunded": "account_updates",
    "account_warning": "account_updates",
    "account": "account_updates",
    "billing": "account_updates",
    "credit_update": "account_updates",
    "catalog_model": "account_updates",
    "enhance_item": "account_updates",
    "try_on_ready": "account_updates",
    # Social activity
    "follow": "social_activity",
    "like": "social_activity",
    "comment": "social_activity",
    "reply": "social_activity",
    "mention": "social_activity",
    "post": "social_activity",
    "user": "social_activity",
    # Community
    "community": "community",
    "giveaway": "community",
    "giveaway_message": "community",
    "challenge": "community",
    # Daily style
    "daily_style": "daily_style",
    "daily_stylist": "daily_style",
    # Product updates (non-marketing, ON by default)
    "product_update": "product_updates",
    "announcement": "product_updates",
    # Promotional (marketing, OFF by default / opt-in)
    "promotion": "promotional",
    "offer": "promotional",
}

# Unknown types resolve here — an on-by-default, non-marketing category. This
# still honors the user's preference for that category (never a bypass, §3).
_DEFAULT_CATEGORY = "account_updates"

# Category → native Android channel (5 channels created in MainActivity, §20).
_CHANNEL_BY_CATEGORY = {
    "referral_rewards": "wtm_account",
    "account_updates": "wtm_account",
    "social_activity": "wtm_social",
    "community": "wtm_community",
    "daily_style": "wtm_style",
    "product_updates": "wtm_updates",
    "promotional": "wtm_updates",
}

# Types that deep-link to the membership/account screen; referral has its own.
# Everything else opens the in-app notification center (always safe to route to).
_ACCOUNT_ROUTE_TYPES = frozenset(
    {
        "payment_issue",
        "subscription_expired",
        "subscription_refunded",
        "account_warning",
        "billing",
    }
)


def _category_for_type(notification_type: str) -> str:
    return _CATEGORY_BY_TYPE.get(notification_type, _DEFAULT_CATEGORY)


def _channel_for_type(notification_type: str) -> str:
    return _CHANNEL_BY_CATEGORY[_category_for_type(notification_type)]


def _route_for_type(notification_type: str) -> str:
    """In-app deep-link route a tapped push opens (validated app-side, §20)."""
    if notification_type == "referral_reward":
        return "/wtm/referral"
    if notification_type in _ACCOUNT_ROUTE_TYPES:
        return "/wtm/paywall"
    return "/wtm/inbox"  # the notification center — safe for any type


async def _push_category_enabled(conn: asyncpg.Connection, user_id: str, category: str) -> bool:
    """Whether the user allows PUSH for [category]. A missing prefs row (or a
    NULL column) means the default — everything on except `promotional`. Fails
    OPEN on any error (a lookup blip never silently drops a real push)."""
    default_on = category != "promotional"
    try:
        row = await conn.fetchrow(
            "select account_updates, referral_rewards, social_activity, community, "
            "daily_style, product_updates, promotional "
            "from public.notification_preferences where user_id = $1::uuid",
            user_id,
        )
    except Exception as exc:
        log.warning("preference lookup failed for %s: %s", user_id, exc)
        return default_on
    if row is None:
        return default_on
    value = row[category]
    return default_on if value is None else bool(value)


# Bounded retry for transient FCM failures — small + capped, never infinite (§6).
_RETRYABLE_ATTEMPTS = 2
_RETRY_BACKOFF_SECONDS = 0.5


async def _send_with_retry(sender, token: str, message: PushMessage) -> DeliveryStatus:
    """Send once; on a *retryable* status try again up to a small cap. A permanent
    (invalid_token) or config (auth_error) status returns immediately — retrying
    those is pointless or harmful (§6)."""
    status = await sender.send(token, message)
    attempts = 1
    while status == DeliveryStatus.retryable and attempts < _RETRYABLE_ATTEMPTS:
        await asyncio.sleep(_RETRY_BACKOFF_SECONDS)
        status = await sender.send(token, message)
        attempts += 1
    return status


async def _invalidate_tokens(user_id: str, tokens: list[str]) -> None:
    """Mark permanently-dead tokens inactive — never DELETE. A muted, a replaced,
    and a dead token are different states (§6); we only stop delivering to a token
    FCM says is gone, and keep the row for audit + re-registration. Best-effort."""
    if not tokens:
        return
    try:
        async with get_pool().acquire() as conn:
            await conn.execute(
                "update public.device_tokens set invalidated_at = now() "
                "where user_id = $1::uuid and token = any($2::text[]) "
                "and invalidated_at is null",
                user_id,
                tokens,
            )
    except Exception as exc:
        log.warning("token prune for %s failed: %s", user_id, exc)


async def push_to_user(user_id: str, message: PushMessage) -> None:
    """Deliver a push to a user's opted-in, still-valid devices via the resolved
    sender (FCM in prod; stub otherwise). Uses its OWN pool connection so it is
    fully decoupled from the caller's request/transaction — the durable
    notification is the source of truth; this is only the delivery channel.

    Best-effort: never raises. Enforces the master per-device `push_opt_in` AND
    the per-category preference, skips already-invalidated tokens, sends to each
    valid device once, prunes tokens FCM reports as permanently dead, and never
    logs a full token. FCM I/O runs with NO db connection held (§20)."""
    try:
        async with get_pool().acquire() as conn:
            # Per-category preference gate (§20) — the durable record already
            # exists; this only suppresses the push channel when muted.
            category = _category_for_type(message.data.get("type", ""))
            if not await _push_category_enabled(conn, user_id, category):
                return
            # Master switch (push_opt_in) + skip invalidated tokens, one query.
            rows = await conn.fetch(
                "select token from public.device_tokens "
                "where user_id = $1::uuid and push_opt_in and invalidated_at is null",
                user_id,
            )
        if not rows:
            return
        sender = get_push_sender()
        delivered = 0
        dead: list[str] = []
        seen: set[str] = set()
        for row in rows:
            token = row["token"]
            if token in seen:  # never double-send to the same device
                continue
            seen.add(token)
            status = await _send_with_retry(sender, token, message)
            if status == DeliveryStatus.ok:
                delivered += 1
            elif status == DeliveryStatus.invalid_token:
                dead.append(token)
            elif status == DeliveryStatus.auth_error:
                # Credential/project failure is identical for every token — stop
                # now rather than storm FCM, and invalidate NOTHING.
                log.error("push aborted for %s: sender credential/config error", user_id)
                break
            # retryable (after bounded retry) → leave the token active for next time.
        if dead:
            await _invalidate_tokens(user_id, dead)
        log.info(
            "push '%s': %d/%d devices via %s (%d pruned)",
            message.data.get("type", "?"),
            delivered,
            len(seen),
            sender.name,
            len(dead),
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
