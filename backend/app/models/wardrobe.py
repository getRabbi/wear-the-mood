from __future__ import annotations

from datetime import date, datetime
from uuid import UUID

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
    # R2 path: the client uploads to R2 via a presigned PUT and sends the object_key
    # instead of image_url. Used only when the write-gate is on (INFRA_UPGRADE Ph.1).
    object_key: str | None = Field(default=None, max_length=512)
    # A cutout that ALREADY EXISTS, produced by a `cutout_temp` job before this
    # item did (0071). Add Garment removes the background first and asks what the
    # piece is afterwards, so by the time the garment is created its cutout has
    # been finished and shown to the user; re-queuing the worker for it would
    # redo minutes of GPU work to arrive at the same image. Supplying this makes
    # the item born `cutout_status = 'done'`. It is validated against a job THIS
    # user owns — a key alone is never trusted (§11).
    cutout_job_id: UUID | None = None
    cost: float | None = Field(default=None, ge=0)
    purchase_date: date | None = None
    tags: list[str] = Field(default_factory=list)


class CutoutJobCreate(BaseModel):
    """Start a background removal that has no garment yet (0071).

    Only the uploaded original's key: the job spends no credits, chooses no
    provider and carries no metadata, because at this point in Add Garment the
    user has not been asked what the piece is — that is the whole point.
    """

    object_key: str = Field(min_length=1, max_length=512)


class WardrobeItemUpdate(BaseModel):
    """Edit/categorize an owned item (real-device polish). Only the user-editable
    metadata fields — name, category, subcategory and color. Every field is
    optional; only the ones the client sends (``model_fields_set``) are written,
    so a partial categorize never clobbers untouched columns. No image/cost edits
    here (those have their own flows)."""

    title: str | None = Field(default=None, max_length=200)
    category: str | None = Field(default=None, max_length=80)
    subcategory: str | None = Field(default=None, max_length=80)
    color: str | None = Field(default=None, max_length=80)


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
    # AI Enhance (BUILD_PROMPT_PRO_PROMAX.md): a signed URL to the enhanced cover
    # (the catalog-ready image) once ready, plus the enhance job status/flag so the
    # closet can show an "Enhancing…" badge and prefer the enhanced cover.
    cover_image_url: str | None = None
    # The cover's own card-sized rendition (512px WebP). Present only once the
    # cover has a thumbnail in the ledger; a card falls back to the full cover
    # when it is absent, which is exactly the pre-thumbnail behaviour.
    cover_thumbnail_url: str | None = None
    ai_enhanced: bool = False
    ai_status: str | None = None  # queued | processing | done | failed
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


class WardrobeGap(BaseModel):
    """A missing essential in the closet (CLAUDE.md §24) — shoppable via the
    suggestion query through /v1/shop/link."""

    category: str
    title: str
    suggestion: str  # search query for shop-the-look
    owned_count: int = 0


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
