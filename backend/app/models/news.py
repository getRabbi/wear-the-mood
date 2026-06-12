from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class NewsItemResponse(BaseModel):
    """A fashion-news item for the industry feed (CLAUDE.md §1 pillar 5). Items
    are team/cron-ingested (RSS + API, summarized) and public to read."""

    id: str
    title: str
    summary: str | None = None
    source: str | None = None
    url: str | None = None
    image_url: str | None = None
    published_at: datetime | None = None
    created_at: datetime
