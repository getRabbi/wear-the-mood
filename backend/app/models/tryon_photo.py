from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class TryonPhotoCreate(BaseModel):
    """A validated full-body photo the user added to their try-on gallery (§1).
    Send exactly one of: `storage_path` (legacy Supabase upload) or `object_key`
    (R2 presigned upload, write-gate on)."""

    storage_path: str | None = Field(default=None, max_length=500)
    object_key: str | None = Field(default=None, max_length=512)
    quality_score: int | None = Field(default=None, ge=0, le=100)


class TryonPhotoResponse(BaseModel):
    id: str
    storage_path: str
    signed_url: str | None = None  # short-lived display URL resolved server-side
    quality_score: int | None = None
    is_selected: bool = False  # == the path mirrored onto profiles.avatar_url
    created_at: datetime
