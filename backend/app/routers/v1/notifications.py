"""In-app notifications feed (CLAUDE.md §1 pillar 4).

Own-row only: a user reads + marks-read only their own notifications (RLS mirrors
this; the backend runs service-role and scopes every query to the JWT user_id,
§11). Notifications are created by the social/try-on flows via
`app.services.notifications`, never by the client.
"""

from __future__ import annotations

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Request, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.rate_limit import enforce_rate_limit
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.notifications import (
    NotificationPreferences,
    NotificationPreferencesUpdate,
    NotificationResponse,
)

router = APIRouter(tags=["notifications"])

_PREF_COLS = "social, referral, account, community, style, promotions"

_SELECT = (
    "select id, actor_id, type, title, body, target_type, target_id, "
    "is_read, created_at from public.notifications"
)


def _to_response(row: asyncpg.Record) -> NotificationResponse:
    return NotificationResponse(
        id=str(row["id"]),
        actor_id=str(row["actor_id"]) if row["actor_id"] else None,
        type=row["type"],
        title=row["title"],
        body=row["body"],
        target_type=row["target_type"],
        target_id=row["target_id"],
        is_read=row["is_read"],
        created_at=row["created_at"],
    )


@router.get("/notifications", response_model=list[NotificationResponse])
async def list_notifications(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(default=50, ge=1, le=100),
) -> list[NotificationResponse]:
    """The caller's notifications, newest first."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            _SELECT + " where user_id = $1::uuid order by created_at desc limit $2",
            user.id,
            limit,
        )
    return [_to_response(r) for r in rows]


@router.get("/notifications/unread-count")
async def unread_count(
    user: CurrentUser = Depends(get_current_user),
) -> dict[str, int]:
    """The caller's unread notification count (server-authoritative — not capped
    by the loaded page). Own-row only (scoped by the JWT user_id, §11)."""
    async with get_pool().acquire() as conn:
        count = await conn.fetchval(
            "select count(*) from public.notifications "
            "where user_id = $1::uuid and is_read = false",
            user.id,
        )
    return {"unread_count": int(count or 0)}


@router.post("/notifications/{notification_id}/read", status_code=204)
async def mark_read(
    notification_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        updated = await conn.fetchval(
            "update public.notifications set is_read = true "
            "where id = $1::uuid and user_id = $2::uuid returning id",
            str(notification_id),
            user.id,
        )
    if updated is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Notification not found.", 404)
    return Response(status_code=204)


@router.post("/notifications/read-all", status_code=204)
async def mark_all_read(
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        await conn.execute(
            "update public.notifications set is_read = true "
            "where user_id = $1::uuid and is_read = false",
            user.id,
        )
    return Response(status_code=204)


@router.get("/notifications/preferences", response_model=NotificationPreferences)
async def get_preferences(
    user: CurrentUser = Depends(get_current_user),
) -> NotificationPreferences:
    """The caller's per-category push preferences (defaults when unset, §20)."""
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            f"select {_PREF_COLS} from public.notification_preferences "
            "where user_id = $1::uuid",
            user.id,
        )
    return NotificationPreferences() if row is None else NotificationPreferences(**dict(row))


@router.patch("/notifications/preferences", response_model=NotificationPreferences)
async def update_preferences(
    body: NotificationPreferencesUpdate,
    request: Request,
    user: CurrentUser = Depends(get_current_user),
) -> NotificationPreferences:
    """Update only the provided categories (§20). Rate limited; server-scoped to
    the caller. These gate PUSH only — the in-app center is unaffected."""
    updates = {k: v for k, v in body.model_dump().items() if v is not None}
    async with get_pool().acquire() as conn:
        await enforce_rate_limit(
            conn, bucket=f"notifprefs:{user.id}", limit=60, window_seconds=3600
        )
        if not updates:
            row = await conn.fetchrow(
                f"select {_PREF_COLS} from public.notification_preferences "
                "where user_id = $1::uuid",
                user.id,
            )
            return (
                NotificationPreferences()
                if row is None
                else NotificationPreferences(**dict(row))
            )
        # Column names come from the fixed pydantic schema (whitelist) — safe.
        cols = list(updates.keys())
        placeholders = ", ".join(f"${i + 2}" for i in range(len(cols)))
        set_clause = ", ".join(f"{c} = excluded.{c}" for c in cols)
        row = await conn.fetchrow(
            f"insert into public.notification_preferences (user_id, {', '.join(cols)}) "
            f"values ($1::uuid, {placeholders}) "
            f"on conflict (user_id) do update set {set_clause}, updated_at = now() "
            f"returning {_PREF_COLS}",
            user.id,
            *[updates[c] for c in cols],
        )
    return NotificationPreferences(**dict(row))
