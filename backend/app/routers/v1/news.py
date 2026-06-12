"""Fashion news feed — the industry feed (CLAUDE.md §1 pillar 5).

Read-only and public content: items are ingested by a cron (RSS + API,
summarized — next step) and stored in news_items (service-role write, public
read). Newest-first by publish time, cursor-paged. Auth is still required so the
client stays uniformly authenticated; no per-user scoping (the feed is global).
"""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.news import NewsItemResponse

router = APIRouter(tags=["news"])

# Order/cursor by publish time, falling back to ingest time when unknown.
_RANK = "coalesce(published_at, created_at)"
_COLUMNS = "id, title, summary, source, url, image_url, published_at, created_at"


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
