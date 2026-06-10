"""Wardrobe CRUD — the digital almira (CLAUDE.md §1, §5).

List / add / remove the user's owned items, always scoped by the JWT user_id
(§11) with RLS as defense-in-depth. No credits and no async job here, so no
idempotency key (§9) is required. Background removal, auto-tagging and
embeddings (§2.2) are gated on storage/AI keys and arrive in later steps; they
will fill cutout_url / thumbnail_url / tags / embedding server-side — for now
the client supplies `image_url` directly.
"""

from __future__ import annotations

from decimal import Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.wardrobe import WardrobeItemCreate, WardrobeItemResponse

router = APIRouter(tags=["wardrobe"])

# Columns returned by every endpoint — static identifiers, no user input.
_COLUMNS = (
    "id, title, category, subcategory, color, pattern, brand, "
    "image_url, cutout_url, thumbnail_url, tags, cost, purchase_date, "
    "last_worn_at, wear_count, created_at"
)


def _to_response(row: asyncpg.Record) -> WardrobeItemResponse:
    return WardrobeItemResponse(
        id=str(row["id"]),
        title=row["title"],
        category=row["category"],
        subcategory=row["subcategory"],
        color=row["color"],
        pattern=row["pattern"],
        brand=row["brand"],
        image_url=row["image_url"],
        cutout_url=row["cutout_url"],
        thumbnail_url=row["thumbnail_url"],
        tags=list(row["tags"] or []),
        cost=float(row["cost"]) if row["cost"] is not None else None,
        purchase_date=row["purchase_date"],
        last_worn_at=row["last_worn_at"],
        wear_count=row["wear_count"],
        created_at=row["created_at"],
    )


@router.get("/wardrobe", response_model=list[WardrobeItemResponse])
async def list_wardrobe(
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeItemResponse]:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"""
            select {_COLUMNS}
              from public.wardrobe_items
             where user_id = $1::uuid
             order by created_at desc
             limit 500
            """,
            user.id,
        )
    return [_to_response(r) for r in rows]


@router.post("/wardrobe", status_code=201, response_model=WardrobeItemResponse)
async def add_wardrobe_item(
    body: WardrobeItemCreate,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    # asyncpg binds the numeric column from Decimal, not float.
    cost = Decimal(str(body.cost)) if body.cost is not None else None
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            f"""
            insert into public.wardrobe_items
              (user_id, title, category, subcategory, color, pattern, brand,
               image_url, cost, purchase_date, tags)
            values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            returning {_COLUMNS}
            """,
            user.id,
            body.title,
            body.category,
            body.subcategory,
            body.color,
            body.pattern,
            body.brand,
            body.image_url,
            cost,
            body.purchase_date,
            body.tags,
        )
    return _to_response(row)


@router.delete("/wardrobe/{item_id}", status_code=204)
async def delete_wardrobe_item(
    item_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    async with get_pool().acquire() as conn:
        deleted = await conn.fetchval(
            """
            delete from public.wardrobe_items
             where id = $1::uuid and user_id = $2::uuid
            returning id
            """,
            str(item_id),
            user.id,
        )
    if deleted is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    return Response(status_code=204)
