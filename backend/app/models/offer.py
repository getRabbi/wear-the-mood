"""Daily Offer models (FEATURES_COMMUNITY_PLUS · Daily Offer)."""

from __future__ import annotations

from pydantic import BaseModel, Field


class Offer(BaseModel):
    id: str
    title: str
    brand: str | None = None
    image_url: str | None = None
    discount_label: str | None = None
    affiliate_url: str  # already attribution-tagged by the backend
    topics: list[str] = Field(default_factory=list)
