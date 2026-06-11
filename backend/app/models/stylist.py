from __future__ import annotations

from pydantic import BaseModel, Field

from app.models.wardrobe import WardrobeItemResponse


class StylistSuggestRequest(BaseModel):
    """Ask the stylist for today's outfit. Coordinates are optional — supplied,
    they add weather context (§2); omitted, the stylist works without it."""

    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    occasion: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=500)


class StylistSuggestResponse(BaseModel):
    """The suggested outfit: a short title + rationale and the chosen items
    (full objects so the app can render them straight away)."""

    title: str
    rationale: str
    items: list[WardrobeItemResponse] = Field(default_factory=list)
