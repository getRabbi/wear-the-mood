from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class ConsentCreate(BaseModel):
    """Record an explicit consent (CLAUDE.md §10), e.g. biometric face/body."""

    consent_type: str = Field(min_length=1, max_length=40)
    version: str = Field(min_length=1, max_length=40)


class ConsentResponse(BaseModel):
    id: str
    consent_type: str
    version: str
    granted: bool
    created_at: datetime
