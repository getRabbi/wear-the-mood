"""Outfit builder — saved combinations of owned items (CLAUDE.md §5).

List / create / remove the user's outfits, always scoped by the JWT user_id
(§11) with RLS as defense-in-depth. Creating an outfit verifies every item_id
is one of the caller's own wardrobe items before saving — the client is never
trusted to reference someone else's pieces (§11). No credits/jobs, so no
idempotency key (§9).
"""

from __future__ import annotations

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.outfit import OutfitCreate, OutfitResponse, OutfitUpdate

router = APIRouter(tags=["outfits"])

# Static identifiers, no user input.
_COLUMNS = "id, name, item_ids, cover_image_url, created_at"


def _to_response(row: asyncpg.Record) -> OutfitResponse:
    return OutfitResponse(
        id=str(row["id"]),
        name=row["name"],
        item_ids=[str(x) for x in (row["item_ids"] or [])],
        cover_image_url=row["cover_image_url"],
        created_at=row["created_at"],
    )


def _dedupe(item_ids: list[UUID]) -> list[UUID]:
    """Preserve order, drop repeats — an outfit lists each piece once."""
    seen: set[UUID] = set()
    out: list[UUID] = []
    for item_id in item_ids:
        if item_id not in seen:
            seen.add(item_id)
            out.append(item_id)
    return out


@router.get("/outfits", response_model=list[OutfitResponse])
async def list_outfits(
    user: CurrentUser = Depends(get_current_user),
) -> list[OutfitResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"""
            select {_COLUMNS}
              from public.outfits
             where user_id = $1::uuid
             order by created_at desc
             limit 500
            """,
            user.id,
        )
    return [_to_response(r) for r in rows]


@router.post("/outfits", status_code=201, response_model=OutfitResponse)
async def create_outfit(
    body: OutfitCreate,
    user: CurrentUser = Depends(get_current_user),
) -> OutfitResponse:
    item_ids = _dedupe(body.item_ids)
    async with get_pool().acquire() as conn:
        # §11: every referenced piece must be the caller's own wardrobe item.
        owned = await conn.fetchval(
            """
            select count(*)
              from public.wardrobe_items
             where user_id = $1::uuid and id = any($2::uuid[])
            """,
            user.id,
            item_ids,
        )
        if owned != len(item_ids):
            raise ApiError(
                ErrorCode.VALIDATION_ERROR,
                "Some items aren't in your wardrobe.",
                422,
            )

        row = await conn.fetchrow(
            f"""
            insert into public.outfits (user_id, name, item_ids, cover_image_url)
            values ($1::uuid, $2, $3::uuid[], $4)
            returning {_COLUMNS}
            """,
            user.id,
            body.name,
            item_ids,
            body.cover_image_url,
        )
    return _to_response(row)


@router.put("/outfits/{outfit_id}", response_model=OutfitResponse)
async def update_outfit(
    outfit_id: UUID,
    body: OutfitUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> OutfitResponse:
    """Edit a saved outfit — replace its name, pieces and cover. Re-checks item
    ownership (§11) and that the outfit is the caller's own."""
    item_ids = _dedupe(body.item_ids)
    async with get_pool().acquire() as conn:
        owned = await conn.fetchval(
            """
            select count(*)
              from public.wardrobe_items
             where user_id = $1::uuid and id = any($2::uuid[])
            """,
            user.id,
            item_ids,
        )
        if owned != len(item_ids):
            raise ApiError(
                ErrorCode.VALIDATION_ERROR,
                "Some items aren't in your wardrobe.",
                422,
            )

        row = await conn.fetchrow(
            f"""
            update public.outfits
               set name = $3, item_ids = $4::uuid[], cover_image_url = $5
             where id = $1::uuid and user_id = $2::uuid
            returning {_COLUMNS}
            """,
            str(outfit_id),
            user.id,
            body.name,
            item_ids,
            body.cover_image_url,
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Outfit not found.", 404)
    return _to_response(row)


@router.delete("/outfits/{outfit_id}", status_code=204)
async def delete_outfit(
    outfit_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        deleted = await conn.fetchval(
            """
            delete from public.outfits
             where id = $1::uuid and user_id = $2::uuid
            returning id
            """,
            str(outfit_id),
            user.id,
        )
    if deleted is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Outfit not found.", 404)
    return Response(status_code=204)
