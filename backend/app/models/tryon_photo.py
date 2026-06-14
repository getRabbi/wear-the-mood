from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class TryonPhotoCreate(BaseModel):
    """A validated full-body photo the user added to their try-on gallery (§1)."""

    storage_path: str = Field(max_length=500)  # <uid>/tryon/<uuid>.jpg in `avatars`
    quality_score: int | None = Field(default=None, ge=0, le=100)


class TryonPhotoResponse(BaseModel):
    id: str
    storage_path: str
    quality_score: int | None = None
    is_selected: bool = False  # == the path mirrored onto profiles.avatar_url
    created_at: datetime
