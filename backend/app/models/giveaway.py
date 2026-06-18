"""Giveaway models (FEATURES_COMMUNITY_PLUS · Giveaway).

Peer-to-peer free clothes. Listings are public; contact happens in-app via a
private claim message — no personal address/phone in public listings (§10).
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class GiveawayCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)
    images: list[str] = Field(default_factory=list)  # public image URLs
    size: str | None = Field(default=None, max_length=60)
    category: str | None = Field(default=None, max_length=60)
    condition: str | None = Field(default=None, max_length=60)
    area_label: str | None = Field(default=None, max_length=120)
    wardrobe_item_id: UUID | None = None

    @field_validator("images")
    @classmethod
    def _clean_images(cls, value: list[str]) -> list[str]:
        return [u.strip() for u in value if u.strip()][:6]


class GiveawayResponse(BaseModel):
    id: str
    owner_id: str
    owner_name: str | None = None
    wardrobe_item_id: str | None = None
    title: str
    description: str | None = None
    images: list[str] = Field(default_factory=list)
    size: str | None = None
    category: str | None = None
    condition: str | None = None
    area_label: str | None = None
    status: str
    is_mine: bool = False
    my_claim_status: str | None = None  # the caller's own claim status, if any
    claim_count: int = 0
    created_at: datetime


class ClaimCreate(BaseModel):
    message: str | None = Field(default=None, max_length=1000)


class ClaimResponse(BaseModel):
    id: str
    giveaway_id: str
    claimer_id: str
    claimer_name: str | None = None
    message: str | None = None
    status: str
    created_at: datetime


class GiveawayStatusUpdate(BaseModel):
    status: Literal["available", "reserved", "claimed", "closed"]


class ClaimDecision(BaseModel):
    status: Literal["accepted", "declined"]
