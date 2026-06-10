"""Profile — display name, avatar (private storage path), body data (CLAUDE.md
§1, §10). Own-row only (§11). The avatar image itself lives in the private
`avatars` bucket; here we store/return only its path — the app mints signed URLs.
"""

from __future__ import annotations

import json

import asyncpg
from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.profile import BodyData, ProfileResponse, ProfileUpdate

router = APIRouter(tags=["profile"])

_SELECT = (
    "select id, display_name, avatar_url, body_data, timezone, onboarding_completed "
    "from public.profiles where id = $1::uuid"
)
_CONSENT_EXISTS = (
    "select exists(select 1 from public.consents "
    "where user_id = $1::uuid and consent_type = 'biometric' and granted)"
)


def _to_profile(row: asyncpg.Record, biometric_consent: bool) -> ProfileResponse:
    body = row["body_data"]
    if isinstance(body, str):  # asyncpg returns jsonb as text
        try:
            body = json.loads(body)
        except ValueError:
            body = None
    return ProfileResponse(
        id=str(row["id"]),
        display_name=row["display_name"],
        avatar_url=row["avatar_url"],
        body_data=BodyData(**body) if isinstance(body, dict) else None,
        timezone=row["timezone"],
        onboarding_completed=row["onboarding_completed"],
        biometric_consent=biometric_consent,
    )


@router.get("/profile", response_model=ProfileResponse)
async def get_profile(user: CurrentUser = Depends(get_current_user)) -> ProfileResponse:
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(_SELECT, user.id)
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Profile not found.", 404)
        consent = await conn.fetchval(_CONSENT_EXISTS, user.id)
    return _to_profile(row, bool(consent))


@router.patch("/profile", response_model=ProfileResponse)
async def update_profile(
    body: ProfileUpdate, user: CurrentUser = Depends(get_current_user)
) -> ProfileResponse:
    body_json = (
        json.dumps(body.body_data.model_dump(exclude_none=True))
        if body.body_data is not None
        else None
    )
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            update public.profiles set
              display_name = coalesce($2, display_name),
              avatar_url   = coalesce($3, avatar_url),
              body_data    = coalesce($4::jsonb, body_data),
              updated_at   = now()
            where id = $1::uuid
            returning id, display_name, avatar_url, body_data, timezone, onboarding_completed
            """,
            user.id,
            body.display_name,
            body.avatar_url,
            body_json,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Profile not found.", 404)
        consent = await conn.fetchval(_CONSENT_EXISTS, user.id)
    return _to_profile(row, bool(consent))
