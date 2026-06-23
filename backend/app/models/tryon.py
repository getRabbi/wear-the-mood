from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

# Max garments in one AI look — the worker chains a provider call per garment,
# so each one adds latency/cost; keep the stack reasonable.
MAX_GARMENTS = 6


class TryOnRequest(BaseModel):
    """Create-job payload. The person image is the user's avatar/selfie; the
    garment source is EXACTLY ONE of:
      - garment_image_urls: the full outfit stack in render order (multi-garment)
      - garment_image_url:   a single garment URL (legacy single-garment)
      - wardrobe_item_id:    one of the user's owned items (resolved server-side)
    """

    person_image_url: str = Field(min_length=1)
    garment_image_url: str | None = None
    garment_image_urls: list[str] | None = None
    wardrobe_item_id: UUID | None = None
    # HD / Try-On Max render — costs 4 credits and is gated to Pro Max
    # (plan.hd_allowed). Default false = the unchanged standard render (1 credit).
    hd: bool = False

    @model_validator(mode="after")
    def _exactly_one_garment_source(self) -> TryOnRequest:
        sources = [
            bool(self.garment_image_url),
            bool(self.wardrobe_item_id),
            bool(self.garment_image_urls),
        ]
        if sum(sources) != 1:
            raise ValueError(
                "Provide exactly one of garment_image_url, garment_image_urls "
                "or wardrobe_item_id."
            )
        if self.garment_image_urls is not None:
            cleaned = [u for u in self.garment_image_urls if u and u.strip()]
            if not cleaned:
                raise ValueError("garment_image_urls must contain at least one image.")
            if len(cleaned) > MAX_GARMENTS:
                raise ValueError(f"At most {MAX_GARMENTS} garments per look.")
            self.garment_image_urls = cleaned
        return self


class TryOnJobResponse(BaseModel):
    job_id: str
    status: str  # queued | processing | done | failed
    result_image_url: str | None = None
    error: str | None = None


class TryOnResultItem(BaseModel):
    """One saved try-on result for the history view. `result_image_url` is a
    short-lived signed URL minted from our private storage."""

    id: str
    result_image_url: str | None = None
    created_at: datetime
