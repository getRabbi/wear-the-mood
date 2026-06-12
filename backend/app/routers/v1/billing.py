"""Billing / subscriptions (CLAUDE.md §18).

Entitlements are owned by the server: the RevenueCat webhook syncs them into the
entitlements table, and premium actions gate on is_premium() — never on a client
claim (§18, §25). The webhook is authenticated by a shared secret, not a user
JWT (it's a server-to-server call from RevenueCat).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Request

from app.core.config import get_settings
from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.billing import EntitlementResponse
from app.models.common import ErrorCode
from app.services.billing import apply_webhook_event, get_entitlement

log = logging.getLogger("fashionos.billing")

router = APIRouter(tags=["billing"])


@router.get("/billing/entitlement", response_model=EntitlementResponse)
async def my_entitlement(
    user: CurrentUser = Depends(get_current_user),
) -> EntitlementResponse:
    """The current user's premium entitlement (reflected by the app; the server
    remains the source of truth for premium actions)."""
    async with get_pool().acquire() as conn:
        return await get_entitlement(conn, user.id)


@router.post("/billing/webhook")
async def revenuecat_webhook(request: Request) -> dict:
    """Receive RevenueCat subscription events and sync the entitlement (§18).
    Authenticated by the shared REVENUECAT_WEBHOOK_AUTH secret, not a user JWT."""
    secret = get_settings().revenuecat_webhook_auth
    if not secret or request.headers.get("authorization", "") != secret:
        raise ApiError(ErrorCode.UNAUTHENTICATED, "Invalid webhook signature.", 401)

    payload = await request.json()
    event = payload.get("event") or {}
    async with get_pool().acquire() as conn:
        applied = await apply_webhook_event(conn, event)
    # Always 200 so RevenueCat doesn't retry-storm; `applied` aids debugging.
    return {"ok": True, "applied": applied}
