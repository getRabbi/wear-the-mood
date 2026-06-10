from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field


class WardrobeItemCreate(BaseModel):
    """Add-to-closet payload (CLAUDE.md §5). The client supplies `image_url`
    directly for now; signed-URL upload + background-removal cutout + auto-tag +
    embedding (§2.2, §8) are gated on storage/AI keys and land in later steps —
    they will populate cutout_url / thumbnail_url / tags / embedding server-side.
    """

    title: str | None = Field(default=None, max_length=200)
    category: str | None = Field(default=None, max_length=80)
    subcategory: str | None = Field(default=None, max_length=80)
    color: str | None = Field(default=None, max_length=80)
    pattern: str | None = Field(default=None, max_length=80)
    brand: str | None = Field(default=None, max_length=120)
    image_url: str | None = Field(default=None, max_length=2000)
    cost: float | None = Field(default=None, ge=0)
    purchase_date: date | None = None
    tags: list[str] = Field(default_factory=list)


class WardrobeItemResponse(BaseModel):
    """A digitized owned item. Keys match the `wardrobe_items` table so the
    Flutter `WardrobeItem` model maps this response directly."""

    id: str
    title: str | None = None
    category: str | None = None
    subcategory: str | None = None
    color: str | None = None
    pattern: str | None = None
    brand: str | None = None
    image_url: str | None = None
    cutout_url: str | None = None
    thumbnail_url: str | None = None
    tags: list[str] = Field(default_factory=list)
    cost: float | None = None
    purchase_date: date | None = None
    last_worn_at: datetime | None = None
    wear_count: int = 0
    created_at: datetime
