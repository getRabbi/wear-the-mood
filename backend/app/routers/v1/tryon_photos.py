"""Try-on photo gallery (CLAUDE.md §1, §10). A user keeps several validated
full-body photos and picks which one is active; the selected photo's storage path
is mirrored onto `profiles.avatar_url` so try-on keeps reading a single path.
Own-row only (§11); the image bytes live in the private `avatars` bucket.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.tryon_photo import TryonPhotoCreate, TryonPhotoResponse

router = APIRouter(tags=["tryon-photos"])

_SELECT = (
    "select id, storage_path, quality_score, created_at from public.tryon_photos "
    "where user_id = $1::uuid order by created_at desc"
)


def _to_resp(row, selected_path: str | None) -> TryonPhotoResponse:
    return TryonPhotoResponse(
        id=str(row["id"]),
        storage_path=row["storage_path"],
        quality_score=row["quality_score"],
        is_selected=selected_path is not None and row["storage_path"] == selected_path,
        created_at=row["created_at"],
    )


@router.get("/tryon-photos", response_model=list[TryonPhotoResponse])
async def list_photos(
    user: CurrentUser = Depends(get_current_user),
) -> list[TryonPhotoResponse]:
    async with get_pool().acquire() as conn:
        selected = await conn.fetchval(
            "select avatar_url from public.profiles where id = $1::uuid", user.id
        )
        rows = await conn.fetch(_SELECT, user.id)
    return [_to_resp(r, selected) for r in rows]


@router.post("/tryon-photos", response_model=TryonPhotoResponse, status_code=201)
async def add_photo(
    body: TryonPhotoCreate, user: CurrentUser = Depends(get_current_user)
) -> TryonPhotoResponse:
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                "insert into public.tryon_photos (user_id, storage_path, quality_score) "
                "values ($1::uuid, $2, $3) "
                "returning id, storage_path, quality_score, created_at",
                user.id,
                body.storage_path,
                body.quality_score,
            )
            # Auto-select the first photo so try-on has something to render.
            selected = await conn.fetchval(
                "select avatar_url from public.profiles where id = $1::uuid", user.id
            )
            if not selected:
                await conn.execute(
                    "update public.profiles set avatar_url = $2, updated_at = now() "
                    "where id = $1::uuid",
                    user.id,
                    body.storage_path,
                )
                selected = body.storage_path
    return _to_resp(row, selected)


@router.delete("/tryon-photos/{photo_id}", status_code=204)
async def delete_photo(
    photo_id: UUID, user: CurrentUser = Depends(get_current_user)
) -> Response:
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            row = await conn.fetchrow(
                "delete from public.tryon_photos where id = $1::uuid and user_id = $2::uuid "
                "returning storage_path",
                str(photo_id),
                user.id,
            )
            if row is None:
                raise ApiError(ErrorCode.NOT_FOUND, "Photo not found.", 404)
            # If we removed the active photo, repoint try-on to the newest remaining.
            selected = await conn.fetchval(
                "select avatar_url from public.profiles where id = $1::uuid", user.id
            )
            if selected == row["storage_path"]:
                newest = await conn.fetchval(
                    "select storage_path from public.tryon_photos where user_id = $1::uuid "
                    "order by created_at desc limit 1",
                    user.id,
                )
                await conn.execute(
                    "update public.profiles set avatar_url = $2, updated_at = now() "
                    "where id = $1::uuid",
                    user.id,
                    newest,
                )
    return Response(status_code=204)
