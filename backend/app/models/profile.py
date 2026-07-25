from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator


def _clean_style_tags(value: list[str] | None) -> list[str] | None:
    """Normalize public style tags: strip, drop a leading '#', cap length, de-dupe
    (case-sensitive), and cap the count. None means 'leave unchanged'."""
    if value is None:
        return None
    cleaned: list[str] = []
    for raw in value:
        tag = raw.strip().lstrip("#")[:24]
        if tag and tag not in cleaned:
            cleaned.append(tag)
    return cleaned[:8]


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
    """Partial update — only the supplied fields change.

    Public-facing fields (`bio`, `style_tags`, `is_public`) are shown on the
    creator's public profile; an empty string / empty list clears them, while
    `None` leaves the field unchanged (CLAUDE.md §1 pillar 4)."""

    display_name: str | None = Field(default=None, max_length=80)
    phone: str | None = Field(default=None, max_length=32)
    avatar_url: str | None = Field(default=None, max_length=500)  # try-on body photo path
    profile_picture_url: str | None = Field(default=None, max_length=500)  # display photo path
    # R2 path (INFRA_UPGRADE Ph.1): the client uploaded to R2 and sends an
    # object_key instead of a Supabase path. Honored only when the write-gate is on.
    avatar_object_key: str | None = Field(default=None, max_length=512)
    profile_picture_object_key: str | None = Field(default=None, max_length=512)
    body_data: BodyData | None = None
    bio: str | None = Field(default=None, max_length=300)
    style_tags: list[str] | None = None
    is_public: bool | None = None
    show_public_closet: bool | None = None

    @field_validator("style_tags")
    @classmethod
    def _validate_tags(cls, value: list[str] | None) -> list[str] | None:
        return _clean_style_tags(value)


class ProfileResponse(BaseModel):
    id: str
    display_name: str | None = None
    phone: str | None = None
    avatar_url: str | None = None  # private storage path/key (raw)
    profile_picture_url: str | None = None  # private storage path/key (raw)
    # Ready-to-use short-lived signed display URLs resolved server-side (R2 or
    # legacy Supabase) — the app shows these instead of self-signing (§11).
    avatar_display_url: str | None = None
    profile_picture_display_url: str | None = None
    body_data: BodyData | None = None
    timezone: str | None = None
    onboarding_completed: bool = False
    biometric_consent: bool = False
    bio: str | None = None
    style_tags: list[str] = Field(default_factory=list)
    is_public: bool = True
    show_public_closet: bool = False
