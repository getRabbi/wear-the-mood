"""Subscription entitlements (CLAUDE.md §18).

Premium access is decided server-side from the entitlements table, which the
RevenueCat webhook keeps in sync — the client's entitlement claim is never
trusted (§18, §25). is_premium() is the gate premium endpoints should call.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

import asyncpg

from app.models.billing import EntitlementResponse

log = logging.getLogger("fashionos.billing")

# RevenueCat event types that REVOKE access; everything else (purchase, renewal,
# cancellation-but-still-active, …) is treated as entitled until expiry.
_EXPIRE_TYPES = {"EXPIRATION", "SUBSCRIPTION_PAUSED"}

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


async def get_entitlement(conn: asyncpg.Connection, user_id: str) -> EntitlementResponse:
    """The user's current entitlement; inactive when there's no row or it has
    expired (defence-in-depth against a stale active flag)."""
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


async def is_premium(conn: asyncpg.Connection, user_id: str) -> bool:
    """Server-side premium gate (§18). Premium endpoints must call this rather
    than trusting any client-supplied entitlement."""
    return (await get_entitlement(conn, user_id)).active


def _expires_at(event: dict) -> datetime | None:
    ms = event.get("expiration_at_ms")
    if not ms:
        return None
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=UTC)
    except (ValueError, TypeError, OverflowError):
        return None


async def apply_webhook_event(conn: asyncpg.Connection, event: dict) -> bool:
    """Map a RevenueCat event onto the user's entitlement row. Best-effort:
    returns False (and logs) on a missing/!uuid app_user_id or an unknown user,
    so the webhook can still 200 and RevenueCat won't retry-storm."""
    app_user_id = event.get("app_user_id")
    if not app_user_id:
        return False
    try:
        UUID(str(app_user_id))  # our app_user_id is the Supabase user id
    except ValueError:
        log.warning("revenuecat event for non-uuid app_user_id %s; ignoring", app_user_id)
        return False

    etype = (event.get("type") or "").upper()
    expires_at = _expires_at(event)
    active = etype not in _EXPIRE_TYPES
    if expires_at is not None and expires_at <= datetime.now(UTC):
        active = False  # already lapsed regardless of event type

    store = (event.get("store") or "").lower() or None
    try:
        await conn.execute(_UPSERT, app_user_id, active, event.get("product_id"), store, expires_at)
    except asyncpg.ForeignKeyViolationError:
        log.warning("revenuecat event for unknown user %s; ignoring", app_user_id)
        return False
    return True
