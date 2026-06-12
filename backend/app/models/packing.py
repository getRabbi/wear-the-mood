from __future__ import annotations

from pydantic import BaseModel, Field

from app.models.wardrobe import WardrobeItemResponse


class PackingPlanRequest(BaseModel):
    """Plan a trip's packing list. Coordinates are optional — supplied, they add
    destination-weather context (§2); omitted, the planner works without it."""

    days: int = Field(ge=1, le=60)
    occasion: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=500)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class PackingPlanResponse(BaseModel):
    """The packing list: a title + notes and the chosen items (full objects so the
    app can render them straight away)."""

    title: str
    notes: str
    items: list[WardrobeItemResponse] = Field(default_factory=list)
