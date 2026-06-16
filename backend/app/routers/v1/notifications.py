"""In-app notifications feed (CLAUDE.md §1 pillar 4).

Own-row only: a user reads + marks-read only their own notifications (RLS mirrors
this; the backend runs service-role and scopes every query to the JWT user_id,
§11). Notifications are created by the social/try-on flows via
`app.services.notifications`, never by the client.
"""

from __future__ import annotations

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.notifications import NotificationResponse

router = APIRouter(tags=["notifications"])

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
