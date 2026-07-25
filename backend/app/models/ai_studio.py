"""AI Studio request/response schemas (BUILD_PROMPT_PRO_PROMAX.md).

Covers the premium, credit-gated AI features that run on the shared `ai_jobs`
pipeline: AI Enhance Item and Catalog Model Shot. (Try-on itself — own_photo /
studio_model — stays on the tryon_jobs models in `app.models.tryon`.)
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class EnhanceItemRequest(BaseModel):
    """Start an AI Enhance on one of the user's closet pieces. The item already
    exists (added with its background-removed cutout); enhancement runs async and
    updates the item's enhanced/cover image on success."""

    wardrobe_item_id: UUID


# The catalog model styles offered in the UI (BUILD_PROMPT_PRO_PROMAX.md — Phase 4).
CATALOG_STYLES = ("studio", "streetwear", "modest", "luxury", "cropped_face")


class CatalogModelRequest(BaseModel):
    """Generate a shopping-site / campaign-style shot of a closet item on an AI
    fashion model. Does NOT alter the wardrobe item's own image."""

    wardrobe_item_id: UUID
    style: str = Field(default="studio")
    # Pro Max HD render — 4 credits, Pro Max only (server-gated). Default = the
    # standard 1-credit render.
    hd: bool = False


class AiJobResponse(BaseModel):
    """A shared ai_jobs row's current state (poll target). `output_url` is a
    short-lived signed URL (or http url) once completed."""

    job_id: str
    job_type: str
    status: str  # internal (legacy): queued | processing | completed | failed
    # External contract (§4.5): queued | preparing | processing | ready | failed.
    state: str = ""
    output_url: str | None = None
    error: str | None = None

    @model_validator(mode="after")
    def _derive_state(self) -> AiJobResponse:
        if not self.state:
            from app.core.status import external_status

            self.state = external_status(self.status)
        return self


class GeneratedImageResponse(BaseModel):
    """One saved AI output for the AI Looks gallery / viewer. `output_url` is a
    short-lived signed URL minted from our storage (or an http url)."""

    id: str
    type: str  # enhanced_item | catalog_model | tryon_result
    output_url: str | None = None
    source_item_id: str | None = None
    is_ai_generated: bool = True
    created_at: datetime


class StudioModelPreset(BaseModel):
    """A curated studio model the user can try clothes on instead of their own
    photo. Only ACTIVE presets (with a real image) are returned."""

    id: str
    name: str
    image_url: str | None = None
    style: str | None = None
    body_type: str | None = None
    skin_tone: str | None = None
    pose_type: str | None = None
    is_pro_only: bool = True
