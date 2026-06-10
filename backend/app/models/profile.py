from __future__ import annotations

from pydantic import BaseModel, Field


class BodyData(BaseModel):
    """Optional body info for fit/styling (CLAUDE.md §1). Minimized collection
    (§10) — height + a coarse body type, nothing more for now."""

    height_cm: int | None = Field(default=None, ge=50, le=280)
    body_type: str | None = Field(default=None, max_length=40)


class ProfileUpdate(BaseModel):
    """Partial update — only the supplied fields change."""

    display_name: str | None = Field(default=None, max_length=80)
    avatar_url: str | None = Field(default=None, max_length=500)  # storage path
    body_data: BodyData | None = None


class ProfileResponse(BaseModel):
    id: str
    display_name: str | None = None
    avatar_url: str | None = None  # private storage path; the app signs it
    body_data: BodyData | None = None
    timezone: str | None = None
    onboarding_completed: bool = False
    biometric_consent: bool = False
