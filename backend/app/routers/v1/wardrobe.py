"""Wardrobe CRUD — the digital almira (CLAUDE.md §1, §5).

List / add / remove the user's owned items, always scoped by the JWT user_id
(§11) with RLS as defense-in-depth. No credits and no async job here, so no
idempotency key (§9) is required. Background removal, auto-tagging and
embeddings (§2.2) are gated on storage/AI keys and arrive in later steps; they
will fill cutout_url / thumbnail_url / tags / embedding server-side — for now
the client supplies `image_url` directly.
"""

from __future__ import annotations

import logging
from decimal import Decimal
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.wardrobe import (
    WardrobeAnalyticsResponse,
    WardrobeGap,
    WardrobeItemCreate,
    WardrobeItemResponse,
    WardrobeItemStat,
)
from app.services.llm import get_embedder

log = logging.getLogger("fashionos.wardrobe")

router = APIRouter(tags=["wardrobe"])

# Columns returned by every endpoint — static identifiers, no user input.
_COLUMNS = (
    "id, title, category, subcategory, color, pattern, brand, "
    "image_url, cutout_url, thumbnail_url, tags, cost, purchase_date, "
    "last_worn_at, wear_count, cutout_status, created_at"
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
        cutout_status=row["cutout_status"],
        created_at=row["created_at"],
    )


# Lean column set for analytics — only what cost-per-wear needs.
_STAT_COLUMNS = "id, title, image_url, cutout_url, thumbnail_url, cost, wear_count"


def _item_stat(row: asyncpg.Record) -> WardrobeItemStat:
    cost = float(row["cost"]) if row["cost"] is not None else None
    wears = row["wear_count"] or 0
    cpw = round(cost / wears, 2) if (cost is not None and wears > 0) else None
    return WardrobeItemStat(
        id=str(row["id"]),
        title=row["title"],
        image_url=row["thumbnail_url"] or row["cutout_url"] or row["image_url"],
        cost=cost,
        wear_count=wears,
        cost_per_wear=cpw,
    )


def _analytics(rows: list[asyncpg.Record]) -> WardrobeAnalyticsResponse:
    """Cost-per-wear + ROI insights over the user's closet (§24). Pure function so
    it's unit-testable without a DB."""
    if not rows:
        return WardrobeAnalyticsResponse()

    priced = [r for r in rows if r["cost"] is not None]
    worn_priced = [r for r in priced if (r["wear_count"] or 0) > 0]
    never_worn_priced = [r for r in priced if (r["wear_count"] or 0) == 0]

    total_spend = round(sum(float(r["cost"]) for r in priced), 2) if priced else None
    priced_wears = sum((r["wear_count"] or 0) for r in priced)
    avg_cpw = (
        round(sum(float(r["cost"]) for r in priced) / priced_wears, 2) if priced_wears > 0 else None
    )

    most_worn_row = max(rows, key=lambda r: r["wear_count"] or 0)
    best_value_row = (
        min(worn_priced, key=lambda r: float(r["cost"]) / r["wear_count"]) if worn_priced else None
    )
    # Biggest waste: priciest never-worn piece, else worst cost-per-wear.
    if never_worn_priced:
        waste_row = max(never_worn_priced, key=lambda r: float(r["cost"]))
    elif worn_priced:
        waste_row = max(worn_priced, key=lambda r: float(r["cost"]) / r["wear_count"])
    else:
        waste_row = None

    return WardrobeAnalyticsResponse(
        item_count=len(rows),
        total_spend=total_spend,
        total_wears=sum((r["wear_count"] or 0) for r in rows),
        never_worn_count=sum(1 for r in rows if (r["wear_count"] or 0) == 0),
        avg_cost_per_wear=avg_cpw,
        most_worn=_item_stat(most_worn_row) if (most_worn_row["wear_count"] or 0) > 0 else None,
        best_value=_item_stat(best_value_row) if best_value_row else None,
        biggest_waste=_item_stat(waste_row) if waste_row else None,
    )


@router.get("/wardrobe/analytics", response_model=WardrobeAnalyticsResponse)
async def wardrobe_analytics(
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeAnalyticsResponse:
    """Cost-per-wear, wardrobe ROI, most/least worn (CLAUDE.md §24)."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"select {_STAT_COLUMNS} from public.wardrobe_items where user_id = $1::uuid",
            user.id,
        )
    return _analytics(rows)


# Capsule-wardrobe essentials (category, title, shop query). A gap is an
# essential the user owns none of — shoppable via /v1/shop/link (§24).
_ESSENTIALS = [
    ("Tops", "A versatile top", "versatile wardrobe tops"),
    ("Bottoms", "A go-to bottom", "versatile trousers"),
    ("Outerwear", "A layering jacket", "lightweight jacket"),
    ("Shoes", "Neutral shoes", "versatile neutral shoes"),
]


def _gaps(counts: dict[str, int]) -> list[WardrobeGap]:
    """Essentials the closet is missing (owns none of). Pure + unit-testable."""
    return [
        WardrobeGap(
            category=category,
            title=title,
            suggestion=query,
            owned_count=counts.get(category.lower(), 0),
        )
        for category, title, query in _ESSENTIALS
        if counts.get(category.lower(), 0) == 0
    ]


@router.get("/wardrobe/gaps", response_model=list[WardrobeGap])
async def wardrobe_gaps(
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeGap]:
    """Closet-gap analysis (CLAUDE.md §24): essentials the user is missing, each
    shoppable through shop-the-look."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            "select lower(category) as category, count(*) as n "
            "from public.wardrobe_items "
            "where user_id = $1::uuid and category is not null "
            "group by lower(category)",
            user.id,
        )
    counts = {r["category"]: r["n"] for r in rows}
    return _gaps(counts)


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


async def _semantic_search(
    conn: asyncpg.Connection, user_id: str, query: str, limit: int
) -> list[asyncpg.Record] | None:
    """Cosine-nearest items by embedding (§2.1). Returns None if no embedder is
    configured or the query embed fails, so the caller can fall back to keyword."""
    embedder = get_embedder()
    if embedder.name == "stub":
        return None
    try:
        vector = await embedder.embed(query)
    except Exception as exc:  # provider/network error -> graceful keyword fallback
        log.warning("search embed failed, falling back to keyword: %s", exc)
        return None
    vec_literal = "[" + ",".join(repr(float(x)) for x in vector) + "]"
    rows = await conn.fetch(
        f"""
        select {_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid and embedding is not null
         order by embedding <=> $2::vector
         limit $3
        """,
        user_id,
        vec_literal,
        limit,
    )
    # Cheap, but still an AI call — record it (§14).
    await conn.execute(
        """
        insert into public.ai_usage_log (user_id, provider, task, images, success)
        values ($1::uuid, $2, 'search_query', 0, true)
        """,
        user_id,
        embedder.name,
    )
    return rows


async def _keyword_search(
    conn: asyncpg.Connection, user_id: str, query: str, limit: int
) -> list[asyncpg.Record]:
    """Fallback when embeddings aren't available: match title/category/color or
    an exact tag."""
    return await conn.fetch(
        f"""
        select {_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid
           and (title ilike $2 or category ilike $2 or subcategory ilike $2
                or color ilike $2 or $3 = any(tags))
         order by created_at desc
         limit $4
        """,
        user_id,
        f"%{query}%",
        query.lower(),
        limit,
    )


@router.get("/wardrobe/search", response_model=list[WardrobeItemResponse])
async def search_wardrobe(
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=20, ge=1, le=100),
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeItemResponse]:
    """Semantic closet search (§2.1, §24). Embeds the query and ranks owned items
    by cosine similarity; falls back to keyword match when embeddings aren't
    available (no OpenAI key, or nothing embedded yet)."""
    async with get_pool().acquire() as conn:
        rows = await _semantic_search(conn, user.id, q, limit)
        if not rows:
            rows = await _keyword_search(conn, user.id, q, limit)
    return [_to_response(r) for r in rows]


@router.post("/wardrobe", status_code=201, response_model=WardrobeItemResponse)
async def add_wardrobe_item(
    body: WardrobeItemCreate,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    # asyncpg binds the numeric column from Decimal, not float.
    cost = Decimal(str(body.cost)) if body.cost is not None else None
    # Queue background removal only when there's an image to process (§2.2).
    cutout_status = "queued" if body.image_url else None
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            f"""
            insert into public.wardrobe_items
              (user_id, title, category, subcategory, color, pattern, brand,
               image_url, cost, purchase_date, tags, cutout_status)
            values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
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
            cutout_status,
        )
    return _to_response(row)


@router.post("/wardrobe/{item_id}/wear", response_model=WardrobeItemResponse)
async def mark_worn(
    item_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> WardrobeItemResponse:
    """Log a wear: +1 wear_count and stamp last_worn_at (feeds cost-per-wear, §24)."""
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            f"""
            update public.wardrobe_items
               set wear_count = wear_count + 1, last_worn_at = now()
             where id = $1::uuid and user_id = $2::uuid
            returning {_COLUMNS}
            """,
            str(item_id),
            user.id,
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
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
