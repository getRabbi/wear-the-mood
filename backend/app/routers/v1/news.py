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

# THE LIFECYCLE GATE. `news_items.status` has been draft/review_required/
# published/archived since 0058, and this endpoint never applied it — RLS is
# `using (true)` for public read, so every unreviewed and every archived story
# was being served to the app as live editorial. "Do not blindly auto-publish
# unknown sources" was enforced at INGEST and then given away at READ.
#
# Named once, here, rather than spelled into each query: the state machine
# belongs to 0058 and the service layer, and a second copy of "which statuses
# are public" is how the two drift.
PUBLIC_STATUS = "published"
_PUBLIC = f"status = '{PUBLIC_STATUS}'"

# A story is eligible for an IMAGE-REQUIRED placement only when its hero image
# has actually been proven to load (0072). Deliberately separate from being a
# valid story: an article with no picture still belongs in the Newsroom, it just
# does not belong on a full-bleed editorial card.
_IMAGE_OK = "image_status = 'ok' and image_url is not null"

# Trend-to-closet (§24): how many matches to show and the cosine-distance cap so
# only genuinely-relevant pieces surface (0 = identical, 2 = opposite).
_MATCH_LIMIT = 12
_MATCH_MAX_DISTANCE = 0.75


@router.get("/news", response_model=list[NewsItemResponse])
async def list_news(
    user: CurrentUser = Depends(get_current_user),
    limit: int = Query(20, ge=1, le=50),
    before: datetime | None = Query(None),
    with_image: bool = Query(
        False,
        description=(
            "Only stories whose hero image has been validated. For image-required "
            "placements (Home 'A quick read', the Discover feature card); the "
            "Newsroom itself must NOT set this, or picture-less stories vanish "
            "from the one surface that should still carry them."
        ),
    ),
) -> list[NewsItemResponse]:
    """Newest-first fashion news. Pass `before` (the rank time of the last item
    seen) to page."""
    where = [_PUBLIC, f"($1::timestamptz is null or {_RANK} < $1::timestamptz)"]
    if with_image:
        where.append(_IMAGE_OK)
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"""
            select {_COLUMNS}
              from public.news_items
             where {" and ".join(where)}
             order by {_RANK} desc
             limit $2
            """,
            before,
            limit,
        )
    return [_to_news_response(r) for r in rows]


def _to_news_response(row: asyncpg.Record) -> NewsItemResponse:
    return NewsItemResponse(
        id=str(row["id"]),
        title=row["title"],
        summary=row["summary"],
        source=row["source"],
        url=row["url"],
        image_url=row["image_url"],
        published_at=row["published_at"],
        created_at=row["created_at"],
    )


@router.get("/news/{news_id}", response_model=NewsItemResponse)
async def get_news_item(
    news_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> NewsItemResponse:
    """ONE story by id.

    Exists so the article reader can stand on its own. It used to resolve the
    story out of whatever the feed happened to have already loaded, which meant a
    push notification or a shared link opened after a cold start found an empty
    list and showed "this story moved on" for a story that was perfectly fine.

    Same public-read scope as the feed: authenticated like every other route, no
    per-user filtering. A missing id is a plain 404, which the app renders as the
    unavailable state rather than a retry loop.
    """
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            # Same lifecycle gate as the feed. A deep link to an unreviewed or
            # archived story must 404 rather than render it — otherwise the
            # editorial state machine is enforced on one route and bypassed by
            # sharing a URL from the other.
            f"select {_COLUMNS} from public.news_items "
            f"where id = $1::uuid and {_PUBLIC}",
            str(news_id),
        )
    if row is None:
        raise ApiError(ErrorCode.NOT_FOUND, "News item not found.", 404)
    return _to_news_response(row)


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
