from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel

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


class NotificationPreferences(BaseModel):
    """Per-category PUSH toggles (§20). These gate delivery only — the in-app
    center always shows every durable notification. Promotions are opt-in (OFF)."""

    social: bool = True
    referral: bool = True
    account: bool = True
    community: bool = True
    style: bool = True
    promotions: bool = False


class NotificationPreferencesUpdate(BaseModel):
    """Partial update — only the provided categories change."""

    social: bool | None = None
    referral: bool | None = None
    account: bool | None = None
    community: bool | None = None
    style: bool | None = None
    promotions: bool | None = None
