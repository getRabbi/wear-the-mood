"""Fashion news feed — the industry feed (CLAUDE.md §1 pillar 5).

Read-only and public content: items are ingested by a cron (RSS + API,
summarized — next step) and stored in news_items (service-role write, public
read). Newest-first by publish time, cursor-paged. Auth is still required so the
client stays uniformly authenticated; no per-user scoping (the feed is global).
"""

from __future__ import annotations

import logging
from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Query

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.news import NewsItemResponse
from app.models.wardrobe import WardrobeItemResponse
from app.routers.v1.wardrobe import _COLUMNS as _WARDROBE_COLUMNS
from app.routers.v1.wardrobe import _to_response
from app.services.llm import get_embedder

log = logging.getLogger("fashionos.news")

router = APIRouter(tags=["news"])

# Order/cursor by publish time, falling back to ingest time when unknown.
_RANK = "coalesce(published_at, created_at)"
_COLUMNS = "id, title, summary, source, url, image_url, published_at, created_at"

# Trend-to-closet (§24): how many matches to show and the cosine-distance cap so
# only genuinely-relevant pieces surface (0 = identical, 2 = opposite).
_MATCH_LIMIT = 12
_MATCH_MAX_DISTANCE = 0.75


@router.get("/news", response_model=list[NewsItemResponse])
async def list_news(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(20, ge=1, le=50),
    before: datetime | None = Query(None),
) -> list[NewsItemResponse]:
    """Newest-first fashion news. Pass `before` (the rank time of the last item
    seen) to page."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"""
            select {_COLUMNS}
              from public.news_items
             where ($1::timestamptz is null or {_RANK} < $1::timestamptz)
             order by {_RANK} desc
             limit $2
            """,
            before,
            limit,
        )
    return [
        NewsItemResponse(
            id=str(r["id"]),
            title=r["title"],
            summary=r["summary"],
            source=r["source"],
            url=r["url"],
            image_url=r["image_url"],
            published_at=r["published_at"],
            created_at=r["created_at"],
        )
        for r in rows
    ]


async def _closet_matches(
    conn: asyncpg.Connection, user_id: str, query: str
) -> list[asyncpg.Record]:
    """Wardrobe pieces nearest the trend text by cosine similarity (§24). Empty
    when embeddings aren't available yet (no OpenAI key, or the worker hasn't
    embedded the closet) — the trend-to-closet match lights up once they are."""
    embedder = get_embedder()
    if embedder.name == "stub" or not query:
        return []
    try:
        vector = await embedder.embed(query)
    except Exception as exc:  # provider/network error -> graceful empty
        log.warning("trend embed failed: %s", exc)
        return []
    vec_literal = "[" + ",".join(repr(float(x)) for x in vector) + "]"
    rows = await conn.fetch(
        f"""
        select {_WARDROBE_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid and embedding is not null
           and (embedding <=> $2::vector) < $3
         order by embedding <=> $2::vector
         limit $4
        """,
        user_id,
        vec_literal,
        _MATCH_MAX_DISTANCE,
        _MATCH_LIMIT,
    )
    # Cheap, but still an AI call — record it (§14).
    await conn.execute(
        """
        insert into public.ai_usage_log (user_id, provider, task, images, success)
        values ($1::uuid, $2, 'trend_match', 0, true)
        """,
        user_id,
        embedder.name,
    )
    return rows


@router.get("/news/{news_id}/closet", response_model=list[WardrobeItemResponse])
async def news_closet_matches(
    news_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> list[WardrobeItemResponse]:
    """Trend-to-closet (§24): the user's own wardrobe pieces that match this
    news item's trend, by semantic similarity over the item embeddings."""
    async with get_pool().acquire() as conn:
        item = await conn.fetchrow(
            "select title, summary from public.news_items where id = $1::uuid",
            str(news_id),
        )
        if item is None:
            raise ApiError(ErrorCode.NOT_FOUND, "News item not found.", 404)
        query = " ".join(p for p in (item["title"], item["summary"]) if p).strip()
        rows = await _closet_matches(conn, user.id, query)
    return [_to_response(r) for r in rows]
