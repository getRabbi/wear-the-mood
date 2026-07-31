"""In-app notifications + push delivery (CLAUDE.md §1 pillar 4, §15, §20).

ONE pipeline for every product event. A caller states what happened; this module
decides the preference category, the Android channel, the in-app deep link and
whether the event is a duplicate — so none of that logic is duplicated (or drifts)
across routers, workers and crons.

Two layers, deliberately independent:

  * the DURABLE record in `public.notifications` is the source of truth. It is
    written first, and the in-app centre works whether or not push is configured;
  * PUSH is best-effort delivery of that record. A failed, muted or undeliverable
    push never prevents the record from existing, and never surfaces to the caller.

Inserts run as the service-role backend (RLS-bypassing); clients can never forge a
notification (insert has no RLS policy). Creation never raises into the caller — a
failed notification must not break the action that triggered it.
"""

from __future__ import annotations

import asyncio
import json
import logging
from dataclasses import dataclass
from urllib.parse import quote

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
    "giveaway_request": "community",
    "giveaway_accepted": "community",
    "giveaway_declined": "community",
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
_ACCOUNT_ROUTE_TYPES = frozenset(
    {
        "payment_issue",
        "subscription_expired",
        "subscription_refunded",
        "account_warning",
        "billing",
    }
)

# The notification centre — always a safe destination for anything we cannot
# resolve to a specific screen.
_INBOX_ROUTE = "/wtm/inbox"


def _category_for_type(notification_type: str) -> str:
    return _CATEGORY_BY_TYPE.get(notification_type, _DEFAULT_CATEGORY)


def _channel_for_type(notification_type: str) -> str:
    return _CHANNEL_BY_CATEGORY[_category_for_type(notification_type)]


def route_for(
    notification_type: str,
    target_type: str | None = None,
    target_id: str | None = None,
) -> str:
    """The in-app route a tapped notification opens (validated app-side, §20).

    Derived from the TARGET, not just the type, so a tap lands on the thing the
    notification is about — the giveaway, the conversation, the post, the profile —
    rather than dumping every event on the generic inbox. Anything unresolvable
    falls back to the inbox, which is always safe to route to.

    The app has its own copy of this mapping for rendering; this one exists so a
    push received while the app is terminated still routes correctly.
    """
    if notification_type == "referral_reward":
        return "/wtm/referral"
    if notification_type in _ACCOUNT_ROUTE_TYPES:
        return "/wtm/paywall"
    if not target_id:
        return _INBOX_ROUTE
    safe = quote(str(target_id), safe="")
    # A chat notification opens the CONVERSATION, not the listing it belongs to.
    # The chat screen is addressed by its giveaway id.
    if notification_type == "giveaway_message" or (target_type or "") == "giveaway_chat":
        return f"/wtm/giveaway-chat?id={safe}"
    match (target_type or "").lower():
        case "giveaway":
            return f"/wtm/giveaways/detail?id={safe}"
        case "offer":
            return f"/wtm/offers/detail?id={safe}"
        case "news":
            return f"/wtm/newsroom/article?id={safe}"
        case "post":
            return f"/wtm/social/post?id={safe}"
        case "user":
            return f"/wtm/user?u={safe}"
        case "wardrobe_item":
            return f"/wtm/closet/item?id={safe}"
        case _:
            return _INBOX_ROUTE


def _route_for_type(notification_type: str) -> str:
    """Back-compat shim for callers that only know the type."""
    return route_for(notification_type)


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


@dataclass(frozen=True)
class NotificationOutcome:
    """What create_notification actually did. `created` is False for a suppressed
    self-notification, a duplicate collapsed by `dedupe_key`, or a failed insert —
    callers that chain follow-up work can branch on it instead of guessing."""

    created: bool
    notification_id: str | None = None


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
    dedupe_key: str | None = None,
    data: dict | None = None,
) -> NotificationOutcome:
    """Insert a notification for [user_id] and queue its push.

    Best-effort in both directions: never notify a user about their own action,
    and swallow any error so the triggering action still succeeds.

    [dedupe_key] makes an event idempotent. A retried request, a re-delivered
    webhook or a second backend listener firing the same event all collapse onto
    the first row (unique per user, migration 0050) instead of stacking duplicate
    notifications — and, because the push is only queued when a row was genuinely
    inserted, they do not re-ping the device either.

    [data] carries structured deep-link metadata (ids only, never PII) so the app
    can open the exact destination.
    """
    if actor_id is not None and actor_id == user_id:
        return NotificationOutcome(False)  # don't notify a user about their own action

    payload = dict(data or {})
    try:
        notification_id = await conn.fetchval(
            """
            insert into public.notifications
              (user_id, actor_id, type, title, body, target_type, target_id,
               dedupe_key, data)
            values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9::jsonb)
            on conflict (user_id, dedupe_key) where dedupe_key is not null
              do nothing
            returning id
            """,
            user_id,
            actor_id,
            type,
            title,
            body,
            target_type,
            target_id,
            dedupe_key,
            json.dumps(payload),
        )
    except Exception as exc:  # never break the caller's main action
        log.warning("notification insert failed for %s (%s): %s", user_id, type, exc)
        return NotificationOutcome(False)  # durable record failed → nothing to deliver

    if notification_id is None:
        if dedupe_key is not None:
            # A duplicate collapsed by dedupe_key. The first notification already
            # exists and was already delivered — sending again would be the noise
            # this key exists to prevent.
            log.info("notification '%s' for %s deduplicated (%s)", type, user_id, dedupe_key)
        else:
            # Without a key the insert cannot conflict, so this means the statement
            # returned nothing at all — worth seeing rather than swallowing.
            log.warning("notification '%s' for %s returned no id", type, user_id)
        return NotificationOutcome(False)

    # Fire-and-forget push delivery (referral + social + all events). The durable
    # record above is the source of truth — this never blocks the caller's request
    # or transaction, and the in-app center works even when push is disabled.
    # Routed to the type's Android channel + a validated in-app deep link (§20).
    route = route_for(type, target_type, target_id)
    push_data = {
        "type": type,
        "route": route,
        "notification_id": str(notification_id),
    }
    if target_type:
        push_data["target_type"] = target_type
    if target_id:
        push_data["target_id"] = str(target_id)
    # FCM data values must be strings; ids only, never free text or PII.
    push_data.update({k: str(v) for k, v in payload.items() if v is not None})

    deliver_push_async(
        user_id,
        PushMessage(
            title=title,
            body=body or "",
            data=push_data,
            android_channel=_channel_for_type(type),
        ),
    )
    return NotificationOutcome(True, str(notification_id))


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
