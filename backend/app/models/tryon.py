from __future__ import annotations

from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class TryOnRequest(BaseModel):
    """Create-job payload. The person image is the user's avatar/selfie; the
    garment is either a supplied URL or one of the user's owned wardrobe items
    (exactly one of the two)."""

    person_image_url: str = Field(min_length=1)
    garment_image_url: str | None = None
    wardrobe_item_id: UUID | None = None

    @model_validator(mode="after")
    def _exactly_one_garment_source(self) -> TryOnRequest:
        if bool(self.garment_image_url) == bool(self.wardrobe_item_id):
            raise ValueError("Provide exactly one of garment_image_url or wardrobe_item_id.")
        return self


class TryOnJobResponse(BaseModel):
    job_id: str
    status: str  # queued | processing | done | failed
    result_image_url: str | None = None
    error: str | None = None
