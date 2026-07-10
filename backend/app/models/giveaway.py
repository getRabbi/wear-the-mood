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
    images: list[str] = Field(default_factory=list)  # full images (R2 CDN or passthrough)
    thumbnails: list[str] = Field(default_factory=list)  # smaller, parallel to images
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


# ── Secret pickup chat (0037) ────────────────────────────────────────────────
# Private owner ↔ accepted-requester coordination, active for 7 days from the
# accept. Text-only, ≤500 chars; bodies are redacted after the chat ends (§10).


class ChatMessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=500)

    @field_validator("body")
    @classmethod
    def _strip_body(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("message can't be empty")
        return value


class ChatMessageResponse(BaseModel):
    id: str
    chat_id: str
    sender_id: str
    is_mine: bool = False
    body: str | None = None  # None once redacted
    body_deleted: bool = False
    created_at: datetime


class PickupPlanUpdate(BaseModel):
    """The pickup plan card — coarse, public-place info ONLY (§10)."""

    area: str | None = Field(default=None, max_length=120)  # suburb / general area
    landmark: str | None = Field(default=None, max_length=160)  # public point
    time_slot: str | None = Field(default=None, max_length=120)
    confirmed: bool = False


class ChatReportCreate(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class PickupChatResponse(BaseModel):
    id: str
    giveaway_id: str
    giveaway_title: str | None = None
    owner_id: str
    requester_id: str
    other_name: str | None = None  # display name of the OTHER participant
    is_owner: bool = False  # whether the caller is the giveaway owner
    status: str  # active | completed | cancelled | expired (locked lifecycle)
    report_flag: bool = False
    pickup_plan: dict = Field(default_factory=dict)
    approved_at: datetime
    expires_at: datetime
    locked_at: datetime | None = None
    completed_at: datetime | None = None
    created_at: datetime
