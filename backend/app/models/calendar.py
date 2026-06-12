from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.models.stylist import StylistSuggestResponse


class CalendarEvent(BaseModel):
    """An upcoming event the user wants an outfit for. The app reads these from
    the device calendar (or the user adds them); only title/time/occasion are
    sent — no other calendar data (privacy, §10)."""

    title: str = Field(min_length=1, max_length=200)
    starts_at: datetime | None = None
    occasion: str | None = Field(default=None, max_length=120)


class CalendarPlanRequest(BaseModel):
    """Plan outfits for a batch of events. Coordinates add weather context (§2)."""

    events: list[CalendarEvent] = Field(min_length=1, max_length=12)
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)


class CalendarEventPlan(BaseModel):
    """One event paired with its suggested outfit."""

    title: str
    starts_at: datetime | None = None
    suggestion: StylistSuggestResponse


class CalendarPlanResponse(BaseModel):
    plans: list[CalendarEventPlan] = Field(default_factory=list)
