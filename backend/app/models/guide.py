"""Daily Guide models (FEATURES_COMMUNITY_PLUS · Daily Guide)."""

from __future__ import annotations

from datetime import date as date_type
from datetime import datetime

from pydantic import BaseModel, Field


class GuideCta(BaseModel):
    label: str
    action: str            # tryon | closet | wardrobe_add | news | ...
    target: str | None = None


class DailyGuide(BaseModel):
    id: str
    date: date_type
    title: str
    summary: str | None = None
    body: str | None = None
    image_url: str | None = None
    topics: list[str] = Field(default_factory=list)
    cta: list[GuideCta] = Field(default_factory=list)
    created_at: datetime
