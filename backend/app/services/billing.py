"""Subscriptions + entitlements (CLAUDE.md §18, §25).

`user_subscriptions` is the AUTHORITY for tier + billing period. The RevenueCat
webhook keeps it in sync, grants the plan's monthly credits on each new period
(idempotent), and processes top-ups; it also keeps the legacy `entitlements` row
updated for the current app's /v1/billing/entitlement contract. Premium gating
reads the SERVER tier — never a client claim. Credits come from plans.monthly_credits.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID

import asyncpg

from app.core.credits import grant_credits
from app.core.plans import Plan, get_plan, plan_for_product
from app.models.billing import EntitlementResponse

log = logging.getLogger("fashionos.billing")

# RevenueCat event types that REVOKE access; everything else (purchase, renewal,
# cancellation-but-still-active, …) is entitled until expiry.
_EXPIRE_TYPES = {"EXPIRATION", "SUBSCRIPTION_PAUSED"}
_PAID_TIERS = ("pro", "pro_max")

# Legacy entitlements row (kept for the existing /v1/billing/entitlement contract).
_UPSERT = """
    insert into public.entitlements
      (user_id, active, product_id, store, expires_at, updated_at)
    values ($1::uuid, $2, $3, $4, $5, now())
    on conflict (user_id) do update
      set active = excluded.active,
          product_id = excluded.product_id,
          store = excluded.store,
          expires_at = excluded.expires_at,
          updated_at = now()
"""

# user_subscriptions — the tier authority.
_SUB_UPSERT = """
    insert into public.user_subscriptions
      (user_id, tier, status, current_period_start, current_period_end,
       store, product_id, updated_at)
    values ($1::uuid, $2, $3, $4, $5, $6, $7, now())
    on conflict (user_id) do update
      set tier = excluded.tier,
          status = excluded.status,
          current_period_start = excluded.current_period_start,
          current_period_end = excluded.current_period_end,
          store = excluded.store,
          product_id = excluded.product_id,
          updated_at = now()
"""


@dataclass(frozen=True)
class Subscription:
    tier: str
    status: str
    current_period_start: datetime | None
    current_period_end: datetime | None


def grant_ref(user_id: str, period_start: datetime) -> str:
    """Stable per-period grant idempotency key (seconds precision) — shared by the
    webhook and the reset cron so each billing period is granted EXACTLY once."""
    return f"grant:{user_id}:{int(period_start.timestamp())}"


# ── reads / gates ───────────────────────────────────────────────────────────


async def get_subscription(conn: asyncpg.Connection, user_id: str) -> Subscription | None:
    row = await conn.fetchrow(
        "select tier, status, current_period_start, current_period_end "
        "from public.user_subscriptions where user_id = $1::uuid",
        user_id,
    )
    if row is None:
        return None
    return Subscription(
        tier=row["tier"],
        status=row["status"],
        current_period_start=row["current_period_start"],
        current_period_end=row["current_period_end"],
    )


def _sub_active(sub: Subscription | None) -> bool:
    if sub is None or sub.tier not in _PAID_TIERS or sub.status not in ("active", "grace"):
        return False
    return sub.current_period_end is None or sub.current_period_end > datetime.now(UTC)


async def current_tier(conn: asyncpg.Connection, user_id: str) -> str:
    """The user's effective tier — 'free' unless they hold an active paid sub."""
    sub = await get_subscription(conn, user_id)
    return sub.tier if _sub_active(sub) else "free"


async def is_premium(conn: asyncpg.Connection, user_id: str) -> bool:
    """Server-side paid-plan gate (§18). True only for an active Pro / Pro Max."""
    return _sub_active(await get_subscription(conn, user_id))


async def user_plan(conn: asyncpg.Connection, user_id: str) -> Plan:
    """The user's current plan (FREE_PLAN when no active sub) — for hd_allowed etc."""
    sub = await get_subscription(conn, user_id)
    return await get_plan(conn, sub.tier if _sub_active(sub) else "free")


async def get_entitlement(conn: asyncpg.Connection, user_id: str) -> EntitlementResponse:
    """Legacy entitlement read for the existing /v1/billing/entitlement endpoint."""
    row = await conn.fetchrow(
        "select active, product_id, store, expires_at "
        "from public.entitlements where user_id = $1::uuid",
        user_id,
    )
    if row is None:
        return EntitlementResponse()
    active = bool(row["active"]) and (
        row["expires_at"] is None or row["expires_at"] > datetime.now(UTC)
    )
    return EntitlementResponse(
        active=active,
        product_id=row["product_id"],
        store=row["store"],
        expires_at=row["expires_at"],
    )


# ── webhook ─────────────────────────────────────────────────────────────────


def _ms_to_dt(ms: object) -> datetime | None:
    if not ms:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=UTC)
    except (ValueError, TypeError, OverflowError):
        return None


async def apply_webhook_event(conn: asyncpg.Connection, event: dict) -> bool:
    """Map a RevenueCat event onto the user's subscription + credits. Best-effort:
    returns False (and logs) on a missing/!uuid app_user_id or unknown user, so the
    webhook still 200s and RevenueCat won't retry-storm."""
    app_user_id = event.get("app_user_id")
    if not app_user_id:
        return False
    try:
        UUID(str(app_user_id))  # our app_user_id is the Supabase user id
    except ValueError:
        log.warning("revenuecat event for non-uuid app_user_id %s; ignoring", app_user_id)
        return False

    product_id = event.get("product_id")
    plan = await plan_for_product(conn, product_id) if product_id else None
    store = (event.get("store") or "").lower() or None
    expires_at = _ms_to_dt(event.get("expiration_at_ms"))

    # ── top-up (one-off, non-subscription product) ──
    if plan is not None and plan.kind == "topup":
        txn_id = str(event.get("id") or event.get("transaction_id") or "")
        if not txn_id:
            return False
        try:
            await conn.execute(
                "insert into public.top_up_purchases "
                "(user_id, sku, credits, store, store_txn_id) "
                "values ($1::uuid, $2, $3, $4, $5) on conflict (store_txn_id) do nothing",
                app_user_id, product_id, plan.monthly_credits, store, txn_id,
            )
        except asyncpg.ForeignKeyViolationError:
            log.warning("top-up for unknown user %s; ignoring", app_user_id)
            return False
        await grant_credits(
            conn, app_user_id, amount=plan.monthly_credits, reason="topup",
            ref=f"topup:{txn_id}", target="topup",
        )
        return True

    # ── subscription ──
    etype = (event.get("type") or "").upper()
    active = etype not in _EXPIRE_TYPES and not (
        expires_at is not None and expires_at <= datetime.now(UTC)
    )

    # Legacy entitlements row (back-compat for the current app).
    try:
        await conn.execute(_UPSERT, app_user_id, active, product_id, store, expires_at)
    except asyncpg.ForeignKeyViolationError:
        log.warning("revenuecat event for unknown user %s; ignoring", app_user_id)
        return False

    if plan is None:
        log.warning(
            "revenuecat sub event for unmapped product %s; entitlement set, tier/credits skipped",
            product_id,
        )
        return True

    period_start = _ms_to_dt(event.get("purchased_at_ms")) or datetime.now(UTC)
    status = "active" if active else "expired"
    await conn.execute(
        _SUB_UPSERT, app_user_id, plan.tier, status, period_start, expires_at, store, product_id
    )

    # Grant the plan's monthly credits on a new ACTIVE period — SET balance (no
    # rollover), idempotent per period via the shared grant_ref.
    if active and plan.monthly_credits > 0:
        await grant_credits(
            conn, app_user_id, amount=plan.monthly_credits, reason="grant",
            ref=grant_ref(app_user_id, period_start), set_plan_balance=True, target="plan",
        )
    return True
