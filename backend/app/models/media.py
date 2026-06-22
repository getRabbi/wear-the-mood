from __future__ import annotations

from pydantic import BaseModel, Field


class UploadUrlRequest(BaseModel):
    """Ask for a one-time R2 upload URL. `sector` decides visibility + bucket
    SERVER-SIDE (never trust a client-supplied visibility, §11)."""

    sector: str = Field(min_length=1, max_length=32)
    content_type: str = Field(min_length=1, max_length=128)
    byte_size: int = Field(gt=0)


class UploadUrlResponse(BaseModel):
    """A presigned PUT the app uploads bytes to directly (§8), plus the stable
    `object_key` it hands to the create endpoint afterwards. `public_url` is set
    only for public sectors (private objects are served via signed URLs)."""

    upload_url: str
    object_key: str
    visibility: str
    content_type: str
    public_url: str | None = None
