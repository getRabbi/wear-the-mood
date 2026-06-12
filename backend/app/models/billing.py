from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class EntitlementResponse(BaseModel):
    """The user's current premium entitlement (CLAUDE.md §18). Source of truth is
    server-side — the client reflects this but never gates premium actions on its
    own claim."""

    active: bool = False
    product_id: str | None = None
    store: str | None = None
    expires_at: datetime | None = None
