from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

# Recognised notification kinds (CLAUDE.md §1 pillar 4). `system` is the catch-all.
NotificationType = Literal[
    "like",
    "comment",
    "follow",
    "try_on_ready",
    "credit_update",
    "challenge",
    "community",
    "premium",
    "system",
]


class NotificationResponse(BaseModel):
    """One in-app notification. Safe fields only — no private actor data beyond a
    display name baked into `title`/`body` at creation time."""

    id: str
    actor_id: str | None = None
    type: str
    title: str
    body: str | None = None
    target_type: str | None = None
    target_id: str | None = None
    is_read: bool = False
    created_at: datetime


# The canonical 7 push categories (CLAUDE.md §2/§3). Ordering here is also the
# order the app renders the toggles in.
PREFERENCE_FIELDS = (
    "account_updates",
    "referral_rewards",
    "social_activity",
    "community",
    "daily_style",
    "product_updates",
    "promotional",
)


class NotificationPreferences(BaseModel):
    """Per-category PUSH toggles (§20). These gate delivery only — the in-app
    center always shows every durable notification. Everything defaults ON except
    `promotional`, which is strictly opt-in (OFF)."""

    account_updates: bool = True
    referral_rewards: bool = True
    social_activity: bool = True
    community: bool = True
    daily_style: bool = True
    product_updates: bool = True
    promotional: bool = False


class NotificationPreferencesUpdate(BaseModel):
    """Partial update — only the provided categories change. `extra=forbid` so an
    unknown/arbitrary field is rejected (422) rather than silently ignored (§4)."""

    model_config = ConfigDict(extra="forbid")

    account_updates: bool | None = None
    referral_rewards: bool | None = None
    social_activity: bool | None = None
    community: bool | None = None
    daily_style: bool | None = None
    product_updates: bool | None = None
    promotional: bool | None = None
