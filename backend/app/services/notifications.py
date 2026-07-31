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
from enum import StrEnum
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
        case "generated_image":
            # AI Looks lists generated outputs newest-first, so the result this
            # notification is about is the first thing on screen. There is no
            # per-image route to address more precisely.
            return "/wtm/looks"
        case "tryon_result":
            return "/tryon/history"
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


class PushOutcome(StrEnum):
    """What one delivery attempt actually achieved.

    The drainer needs this to settle a row honestly. Collapsing all of these to
    "done" is what made a transient FCM outage indistinguishable from a
    successful send — the row was marked delivered and never retried.

    Terminal (settle, never retry):
      * delivered      — at least one device accepted it;
      * suppressed     — the user muted this category; not sending IS the
                         correct outcome, and retrying cannot change it;
      * no_tokens      — no registered, opted-in device. Retrying cannot help:
                         a device that registers later gets FUTURE pushes, and
                         the durable in-app notification is already waiting;
      * all_invalid    — every target token is permanently dead (and now
                         invalidated). Nothing left to deliver to.

    Retryable (leave pending, record why):
      * transient      — network/provider blip;
      * auth_error     — FCM credentials or project misconfigured. Explicitly
                         NOT terminal: once the config is corrected the backlog
                         should still go out, and no user token is at fault;
      * failed         — unexpected. Contained to this row.
    """

    delivered = "delivered"
    suppressed = "suppressed"
    no_tokens = "no_tokens"
    all_invalid = "all_invalid"
    transient = "transient"
    auth_error = "auth_error"
    failed = "failed"

    @property
    def is_terminal(self) -> bool:
        return self in (
            PushOutcome.delivered,
            PushOutcome.suppressed,
            PushOutcome.no_tokens,
            PushOutcome.all_invalid,
        )


async def push_to_user(user_id: str, message: PushMessage) -> PushOutcome:
    """Deliver a push to a user's opted-in, still-valid devices via the resolved
    sender (FCM in prod; stub otherwise). Uses its OWN pool connection so it is
    fully decoupled from the caller's request/transaction — the durable
    notification is the source of truth; this is only the delivery channel.

    Never raises: returns a [PushOutcome] instead, so a caller (the outbox
    drainer) can settle or retry on evidence rather than on assumption.

    Enforces the master per-device `push_opt_in` AND the per-category preference,
    skips already-invalidated tokens, sends to each valid device once, prunes
    tokens FCM reports as permanently dead, and never logs a full token. FCM I/O
    runs with NO db connection held (§20)."""
    try:
        async with get_pool().acquire() as conn:
            # Per-category preference gate (§20) — the durable record already
            # exists; this only suppresses the push channel when muted.
            category = _category_for_type(message.data.get("type", ""))
            if not await _push_category_enabled(conn, user_id, category):
                return PushOutcome.suppressed
            # Master switch (push_opt_in) + skip invalidated tokens, one query.
            rows = await conn.fetch(
                "select token from public.device_tokens "
                "where user_id = $1::uuid and push_opt_in and invalidated_at is null",
                user_id,
            )
        if not rows:
            return PushOutcome.no_tokens
        sender = get_push_sender()
        delivered = 0
        dead: list[str] = []
        transient = 0
        auth_failed = False
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
                auth_failed = True
                break
            else:
                transient += 1
        # Only tokens FCM called permanently dead. A transient or credential
        # failure must never cost a user their device registration.
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
        if delivered:
            return PushOutcome.delivered
        if auth_failed:
            return PushOutcome.auth_error
        if transient:
            return PushOutcome.transient
        # Nothing delivered, nothing retryable, and every token we tried is dead.
        return PushOutcome.all_invalid
    except Exception as exc:  # delivery is best-effort — never surface
        log.warning("push to %s failed: %s", user_id, exc)
        return PushOutcome.failed


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
    """Record a notification for [user_id] and its intent to push.

    BOTH writes go through the CALLER'S connection, so both participate in
    whatever transaction the caller is in. That is the whole point: if the
    triggering action rolls back, the notification and the push intent roll back
    with it, and no push can be sent for something that did not happen. Delivery
    happens later, from committed rows only, in [drain_notification_outbox].

    Best-effort in both directions: never notify a user about their own action,
    and swallow any error so the triggering action still succeeds — failing to
    notify must not fail the like/comment/accept that caused it.

    [dedupe_key] makes an event idempotent. A retried request, a re-delivered
    webhook or a second backend listener firing the same event all collapse onto
    the first row (unique per user, migration 0050) instead of stacking duplicate
    notifications — and, because the outbox row is only written when a
    notification row was genuinely inserted, they do not re-ping the device either.

    [data] carries structured deep-link metadata (ids only, never PII) so the app
    can open the exact destination.
    """
    if actor_id is not None and actor_id == user_id:
        return NotificationOutcome(False)  # don't notify a user about their own action

    payload = dict(data or {})
    try:
        # SAVEPOINT. Catching an SQL error in Python does NOT restore a Postgres
        # transaction — once a statement fails, the whole transaction is aborted
        # and every later statement errors with "current transaction is aborted".
        # Without this nesting, a notification problem (a missing column before
        # migration 0050/0051, a constraint, a type error) would take the ACCEPT,
        # the job completion or the refund down with it.
        #
        # asyncpg maps a nested `transaction()` onto SAVEPOINT/ROLLBACK TO, so a
        # failure here unwinds only these two inserts and leaves the caller's
        # transaction usable. It also makes the pair ATOMIC: notification and
        # outbox row commit together or not at all, which is what stops a
        # notification existing with no push intent (or the reverse).
        async with conn.transaction():
            return await _persist_notification(
                conn,
                user_id=user_id,
                type=type,
                title=title,
                actor_id=actor_id,
                body=body,
                target_type=target_type,
                target_id=target_id,
                dedupe_key=dedupe_key,
                payload=payload,
            )
    except Exception as exc:
        # Never break the caller's main action. The savepoint has already rolled
        # back, so the outer transaction is still healthy and can commit.
        log.warning("notification insert failed for %s (%s): %s", user_id, type, exc)
        return NotificationOutcome(False)


async def _persist_notification(
    conn: asyncpg.Connection,
    *,
    user_id: str,
    type: str,
    title: str,
    actor_id: str | None,
    body: str | None,
    target_type: str | None,
    target_id: str | None,
    dedupe_key: str | None,
    payload: dict,
) -> NotificationOutcome:
    """The two inserts, inside the caller's savepoint.

    ATOMIC BY POLICY: the notification and its push intent commit together or
    roll back together. Raising anywhere here unwinds both — and nothing outside
    them — so there is never a notification with no push intent, nor a push
    intent pointing at a notification that does not exist.
    """
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

    if notification_id is None:
        if dedupe_key is not None:
            # A duplicate collapsed by dedupe_key. The first notification already
            # exists and its push is already queued — queueing another is exactly
            # the noise this key exists to prevent.
            log.info("notification '%s' for %s deduplicated (%s)", type, user_id, dedupe_key)
        else:
            # Without a key the insert cannot conflict, so this means the statement
            # returned nothing at all — worth seeing rather than swallowing.
            log.warning("notification '%s' for %s returned no id", type, user_id)
        return NotificationOutcome(False)

    # Queue delivery IN THE SAME TRANSACTION as the notification. The route is
    # resolved now so a push opened from a terminated app still lands on the right
    # screen without the client having to re-derive it (§20).
    message = PushMessage(
        title=title,
        body=body or "",
        data=push_data_for(
            type,
            target_type=target_type,
            target_id=target_id,
            notification_id=str(notification_id),
            extra=payload,
        ),
        android_channel=_channel_for_type(type),
    )
    # NOT wrapped in its own try: a failure here must roll the notification back
    # too, so the pair stays atomic. The caller's savepoint contains it, and the
    # business transaction is unaffected either way.
    await conn.execute(
        """
        insert into public.notification_outbox (notification_id, user_id, payload)
        values ($1::uuid, $2::uuid, $3::jsonb)
        on conflict (notification_id) do nothing
        """,
        str(notification_id),
        user_id,
        json.dumps(
            {
                "title": message.title,
                "body": message.body,
                "data": message.data,
                "android_channel": message.android_channel,
            }
        ),
    )

    return NotificationOutcome(True, str(notification_id))


def push_data_for(
    notification_type: str,
    *,
    target_type: str | None,
    target_id: str | None,
    notification_id: str,
    extra: dict | None = None,
) -> dict[str, str]:
    """The FCM `data` payload for a notification. Every value is a string (FCM
    rejects anything else) and carries ids only — never free text or PII (§10)."""
    out = {
        "type": notification_type,
        "route": route_for(notification_type, target_type, target_id),
        "notification_id": notification_id,
    }
    if target_type:
        out["target_type"] = target_type
    if target_id:
        out["target_id"] = str(target_id)
    out.update({k: str(v) for k, v in (extra or {}).items() if v is not None})
    return out


# ── outbox drain: delivery of COMMITTED push intents ─────────────────────────
# Runs in the worker loop (~2s idle cadence) with an hourly cron backstop for
# worker downtime. Claims use FOR UPDATE SKIP LOCKED so two drainers can never
# send the same row twice.

#: Give up after this many attempts. A push is disposable — the durable in-app
#: notification already exists, so retrying forever buys nothing.
_MAX_PUSH_ATTEMPTS = 3

#: A claim older than this belonged to a drainer that died mid-send; reclaim it.
_CLAIM_STALE_MINUTES = 5

_CLAIM_OUTBOX = f"""
    update public.notification_outbox
       set locked_at = now(), attempts = attempts + 1
     where id in (
       select id from public.notification_outbox
        where status = 'pending'
          and attempts < {_MAX_PUSH_ATTEMPTS}
          and (locked_at is null
               or locked_at < now() - interval '{_CLAIM_STALE_MINUTES} minutes')
        order by created_at
        for update skip locked
        limit $1
     )
    returning id, user_id, payload, attempts
"""

# Terminal settle. `delivered_at` is only stamped for a real delivery; the other
# terminal states record WHY nothing was sent, which is not the same thing.
_SETTLE_OUTBOX = """
    update public.notification_outbox
       set status = $2,
           delivered_at = case when $2 = 'delivered' then now() else delivered_at end,
           locked_at = null,
           last_error = null
     where id = $1::uuid
"""

# Retryable: leave it pending, release the claim so it is picked up again, and
# record a SAFE category (never a token, URL or payload).
_RETRY_OUTBOX = """
    update public.notification_outbox
       set locked_at = null, last_error = $2
     where id = $1::uuid
"""

# Dead letter. Kept forever until reviewed — an exhausted push is evidence of a
# delivery problem, and calling it "delivered" would erase that evidence.
_EXHAUST_OUTBOX = """
    update public.notification_outbox
       set status = 'exhausted', locked_at = null, last_error = $2
     where id = $1::uuid
"""

#: PushOutcome -> the terminal `status` it settles as.
_TERMINAL_STATUS = {
    PushOutcome.delivered: "delivered",
    PushOutcome.suppressed: "suppressed",
    PushOutcome.no_tokens: "undeliverable",
    PushOutcome.all_invalid: "undeliverable",
}


async def drain_notification_outbox(*, limit: int = 20) -> int:
    """Deliver committed push intents. Returns how many were actually DELIVERED.

    Every row it reads is, by construction, from a transaction that COMMITTED —
    which is what makes a tap safe: the notification, the chat and the job it
    points at are all visible by the time the device is pinged.

    Each row is settled on the evidence [push_to_user] returns, never on the
    assumption that having tried is the same as having succeeded:

      * delivered / suppressed / undeliverable → terminal, no retry;
      * transient / auth-config / unexpected   → stays pending and is retried,
        with a safe error category recorded;
      * out of attempts                        → `exhausted`, a dead letter that
        is explicitly NOT "delivered".

    AT-LEAST-ONCE, honestly: if FCM accepts a push and this process dies before
    the row is settled, the claim ages out and the push is sent again. A
    duplicate notification is strictly better than a silently lost one, but it
    IS possible — the outbox does not promise exactly-once.

    Uses its own short-lived connections and holds NONE of them across the FCM
    call (§20), so a slow provider cannot tie up the pool. Never raises.
    """
    try:
        async with get_pool().acquire() as conn:
            rows = await conn.fetch(_CLAIM_OUTBOX, limit)
    except Exception as exc:
        log.warning("outbox claim failed: %s", exc)
        return 0
    if not rows:
        return 0

    results: list[tuple[str, PushOutcome, int]] = []
    for row in rows:
        row_id = str(row["id"])
        try:
            payload = row["payload"]
            if isinstance(payload, str):
                payload = json.loads(payload)
            outcome = await push_to_user(
                str(row["user_id"]),
                PushMessage(
                    title=payload.get("title", ""),
                    body=payload.get("body", ""),
                    data=payload.get("data") or {},
                    android_channel=payload.get("android_channel"),
                ),
            )
        except Exception as exc:
            # One malformed or exploding row must not abandon the rest of the
            # batch; contain it and carry on.
            log.warning("outbox row %s failed: %s", row_id, type(exc).__name__)
            outcome = PushOutcome.failed
        results.append((row_id, outcome, int(row["attempts"])))

    delivered = 0
    for row_id, outcome, attempts in results:
        try:
            async with get_pool().acquire() as conn:
                if outcome.is_terminal:
                    await conn.execute(_SETTLE_OUTBOX, row_id, _TERMINAL_STATUS[outcome])
                    if outcome is PushOutcome.delivered:
                        delivered += 1
                elif attempts >= _MAX_PUSH_ATTEMPTS:
                    # Attempts already incremented by the claim, so this WAS the
                    # last one. Dead-letter it rather than lie about delivery.
                    await conn.execute(_EXHAUST_OUTBOX, row_id, outcome.value)
                    log.error(
                        "outbox row %s exhausted after %d attempts (%s)",
                        row_id,
                        attempts,
                        outcome.value,
                    )
                else:
                    await conn.execute(_RETRY_OUTBOX, row_id, outcome.value)
        except Exception as exc:
            # Settling failed: the row keeps its claim, ages out of the claim
            # window and is retried. See the at-least-once note above.
            log.warning("outbox settle failed for %s: %s", row_id, exc)

    log.info(
        "outbox: %d claimed, %d delivered, %s",
        len(results),
        delivered,
        ", ".join(
            f"{o.value}={sum(1 for _, x, _ in results if x is o)}"
            for o in PushOutcome
            if any(x is o for _, x, _ in results) and o is not PushOutcome.delivered
        )
        or "no other outcomes",
    )
    return delivered


#: Delivered/suppressed/undeliverable rows are audit trail, not state. Keep them
#: long enough to answer "was this push sent?" and no longer. `exhausted` rows
#: are deliberately excluded — a dead letter stays until someone looks at it.
OUTBOX_RETENTION_DAYS = 30

_PRUNE_OUTBOX = f"""
    delete from public.notification_outbox
     where id in (
       select id from public.notification_outbox
        where status in ('delivered', 'suppressed', 'undeliverable')
          and delivered_at is not null
          and delivered_at < now() - interval '{OUTBOX_RETENTION_DAYS} days'
        order by delivered_at
        limit $1
     )
"""


async def prune_notification_outbox(*, batch: int = 1000, max_batches: int = 20) -> int:
    """Delete settled outbox rows past the retention window. Returns the count.

    Bounded on both axes so a long-neglected table cannot turn cleanup into a
    table-locking marathon. Only ever touches rows that are BOTH terminal and
    stamped with a `delivered_at` in the past — pending, claimed, retryable and
    exhausted rows are never eligible.
    """
    removed = 0
    for _ in range(max_batches):
        try:
            async with get_pool().acquire() as conn:
                status = await conn.execute(_PRUNE_OUTBOX, batch)
        except Exception as exc:
            log.warning("outbox prune failed: %s", exc)
            break
        # asyncpg returns e.g. "DELETE 137".
        count = int(status.rsplit(" ", 1)[-1]) if status else 0
        removed += count
        if count < batch:
            break
    if removed:
        log.info("outbox prune removed %d settled row(s)", removed)
    return removed


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
