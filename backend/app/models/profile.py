from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Gender = Literal["female", "male", "non_binary", "prefer_not_to_say"]
AgeRange = Literal["under_18", "18_24", "25_34", "35_44", "45_54", "55_plus"]
FitPreference = Literal["slim", "regular", "relaxed"]


class BodyData(BaseModel):
    """Body info that drives try-on fit + the stylist (CLAUDE.md §1). Sensitive
    (§10): collected only behind explicit biometric consent, every field optional,
    and serialized with `exclude_none` so we never persist empty keys."""

    gender: Gender | None = None
    height_cm: int | None = Field(default=None, ge=50, le=280)
    weight_kg: int | None = Field(default=None, ge=20, le=400)
    age_range: AgeRange | None = None
    body_type: str | None = Field(default=None, max_length=40)
    fit_preference: FitPreference | None = None
    skin_tone: str | None = Field(default=None, max_length=24)


class ProfileUpdate(BaseModel):
    """Partial update — only the supplied fields change."""

    display_name: str | None = Field(default=None, max_length=80)
    phone: str | None = Field(default=None, max_length=32)
    avatar_url: str | None = Field(default=None, max_length=500)  # try-on body photo path
    profile_picture_url: str | None = Field(default=None, max_length=500)  # display photo path
    body_data: BodyData | None = None


class ProfileResponse(BaseModel):
    id: str
    display_name: str | None = None
    phone: str | None = None
    avatar_url: str | None = None  # private storage path; the app signs it
    profile_picture_url: str | None = None  # private storage path; the app signs it
    body_data: BodyData | None = None
    timezone: str | None = None
    onboarding_completed: bool = False
    biometric_consent: bool = False
