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
    cutout_status: str | None = None  # queued | processing | done | failed | skipped
    created_at: datetime


class WardrobeItemStat(BaseModel):
    """A single highlighted item in the wardrobe analytics (CLAUDE.md §24)."""

    id: str
    title: str | None = None
    image_url: str | None = None
    cost: float | None = None
    wear_count: int = 0
    cost_per_wear: float | None = None  # cost / wears; None when never worn or no cost


class WardrobeAnalyticsResponse(BaseModel):
    """Cost-per-wear + wardrobe ROI insights (CLAUDE.md §24, pillar 2 data moat)."""

    item_count: int = 0
    total_spend: float | None = None
    total_wears: int = 0
    never_worn_count: int = 0
    avg_cost_per_wear: float | None = None  # total spend / total wears (priced items)
    most_worn: WardrobeItemStat | None = None
    best_value: WardrobeItemStat | None = None  # lowest cost-per-wear
    biggest_waste: WardrobeItemStat | None = None  # priciest piece worn least
