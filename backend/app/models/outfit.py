from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class OutfitCreate(BaseModel):
    """Compose a saved outfit (CLAUDE.md §5) from owned wardrobe items. The
    server verifies every id is one of the caller's wardrobe items (§11) before
    saving. `cover_image_url` is optional for now; a generated collage / try-on
    cover lands in a later step."""

    name: str | None = Field(default=None, max_length=200)
    item_ids: list[UUID] = Field(min_length=1, max_length=30)
    cover_image_url: str | None = Field(default=None, max_length=2000)


class OutfitResponse(BaseModel):
    id: str
    name: str | None = None
    item_ids: list[str] = Field(default_factory=list)
    cover_image_url: str | None = None
    created_at: datetime
