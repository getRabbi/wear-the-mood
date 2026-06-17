"""Profile — display name, avatar (private storage path), body data (CLAUDE.md
§1, §10). Own-row only (§11). The avatar image itself lives in the private
`avatars` bucket; here we store/return only its path — the app mints signed URLs.
"""

from __future__ import annotations

import json

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.profile import BodyData, ProfileResponse, ProfileUpdate
from app.models.push import DeviceTokenRegister

router = APIRouter(tags=["profile"])

_SELECT = (
    "select id, display_name, phone, avatar_url, profile_picture_url, body_data, "
    "timezone, onboarding_completed, bio, style_tags, is_public, show_public_closet "
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
        phone=row["phone"],
        avatar_url=row["avatar_url"],
        profile_picture_url=row["profile_picture_url"],
        body_data=BodyData(**body) if isinstance(body, dict) else None,
        timezone=row["timezone"],
        onboarding_completed=row["onboarding_completed"],
        biometric_consent=biometric_consent,
        bio=row["bio"],
        style_tags=list(row["style_tags"]) if row["style_tags"] is not None else [],
        is_public=row["is_public"],
        show_public_closet=row["show_public_closet"],
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
              display_name        = coalesce($2, display_name),
              phone               = coalesce($3, phone),
              avatar_url          = coalesce($4, avatar_url),
              profile_picture_url = coalesce($5, profile_picture_url),
              body_data           = coalesce($6::jsonb, body_data),
              bio                 = coalesce($7, bio),
              style_tags          = coalesce($8::text[], style_tags),
              is_public           = coalesce($9, is_public),
              show_public_closet  = coalesce($10, show_public_closet),
              updated_at          = now()
            where id = $1::uuid
            returning id, display_name, phone, avatar_url, profile_picture_url,
                      body_data, timezone, onboarding_completed,
                      bio, style_tags, is_public, show_public_closet
            """,
            user.id,
            body.display_name,
            body.phone,
            body.avatar_url,
            body.profile_picture_url,
            body_json,
            body.bio,
            body.style_tags,
            body.is_public,
            body.show_public_closet,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Profile not found.", 404)
        consent = await conn.fetchval(_CONSENT_EXISTS, user.id)
    return _to_profile(row, bool(consent))


@router.put("/profile/push-token", status_code=204)
async def register_push_token(
    body: DeviceTokenRegister, user: CurrentUser = Depends(get_current_user)
) -> Response:
    """Register/refresh this device's FCM token for the daily push (§20). Stores
    the device timezone on the profile so the morning push fires at local AM."""
    async with get_pool().acquire() as conn:
        if body.timezone is not None:
            valid = await conn.fetchval(
                "select exists(select 1 from pg_timezone_names where name = $1)",
                body.timezone,
            )
            if not valid:
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Unknown timezone.", 422)
            await conn.execute(
                "update public.profiles set timezone = $2, updated_at = now() where id = $1::uuid",
                user.id,
                body.timezone,
            )
        await conn.execute(
            """
            insert into public.device_tokens (user_id, token, platform, push_opt_in)
            values ($1::uuid, $2, $3, true)
            on conflict (user_id, token) do update
              set platform = excluded.platform,
                  push_opt_in = true,
                  updated_at = now()
            """,
            user.id,
            body.token,
            body.platform,
        )
    return Response(status_code=204)


@router.delete("/profile/push-token", status_code=204)
async def delete_push_token(
    token: str = Query(min_length=1, max_length=4096),
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Unregister a device token (logout / notifications turned off, §20)."""
    async with get_pool().acquire() as conn:
        await conn.execute(
            "delete from public.device_tokens where user_id = $1::uuid and token = $2",
            user.id,
            token,
        )
    return Response(status_code=204)
