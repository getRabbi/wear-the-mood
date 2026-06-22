"""Client image uploads via R2 presigned PUT URLs (CLAUDE.md §8, §11;
INFRA_UPGRADE Phase 1B · COMMIT 3).

The app never holds R2 keys (§11): it asks here for a one-time PUT URL, uploads
the bytes STRAIGHT to R2 (no proxy through FastAPI, §8), then hands the returned
``object_key`` to the relevant create endpoint, which records the media_assets
row. Visibility + bucket are decided SERVER-SIDE from the sector — a client can
never make a private sector public.

Gated by ``STORAGE_WRITES``: until it is flipped to ``r2`` (after the 1C backfill)
this endpoint returns 503 and the app keeps using the legacy Supabase upload.
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import uuid4

from fastapi import APIRouter, Depends

from app.core.config import get_settings
from app.core.errors import ApiError
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.media import UploadUrlRequest, UploadUrlResponse
from app.services.media import get_storage_provider
from app.services.media.base import Visibility
from app.services.media.r2 import ext_for, public_url_for

router = APIRouter(tags=["media"])


@dataclass(frozen=True)
class _Sector:
    visibility: Visibility
    owner_kind: str
    role: str


# The only upload sectors a client may request. Visibility matches the approved
# 1B-STEP-0 classification — set here, never by the client.
_SECTORS: dict[str, _Sector] = {
    "wardrobe": _Sector("private", "wardrobe_item", "original"),
    "avatar": _Sector("private", "profile", "avatar"),
    "profile_pic": _Sector("private", "profile", "profile_pic"),
    "tryon_photo": _Sector("private", "tryon_photo", "tryon_photo"),
    "post": _Sector("public", "post", "post"),
    "giveaway": _Sector("public", "giveaway", "giveaway"),
}
_ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
_MAX_BYTES = 12 * 1024 * 1024  # 12 MB — generous after client compression (§8)


@router.post("/media/upload-url", response_model=UploadUrlResponse)
async def create_upload_url(
    body: UploadUrlRequest,
    user: CurrentUser = Depends(get_current_user),
) -> UploadUrlResponse:
    settings = get_settings()
    if not settings.r2_writes_enabled:
        # Gate closed → app falls back to the legacy Supabase upload path.
        raise ApiError(ErrorCode.PROVIDER_ERROR, "Direct image uploads are not enabled.", 503)

    sector = _SECTORS.get(body.sector)
    if sector is None:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Unknown upload sector.", 422)

    content_type = body.content_type.lower().split(";")[0].strip()
    if content_type not in _ALLOWED_TYPES:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Unsupported image type.", 422)
    if body.byte_size > _MAX_BYTES:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Image too large.", 422)

    # Server-built key under the user's own folder (the only place uid is trusted).
    object_key = f"{user.id}/{body.sector}/{uuid4().hex}{ext_for(content_type)}"

    # r2_writes_enabled guarantees the R2 provider; presign_put is R2-specific.
    provider = get_storage_provider()
    upload_url = await provider.presign_put(  # type: ignore[attr-defined]
        object_key=object_key, visibility=sector.visibility, content_type=content_type
    )
    public_url = (
        public_url_for(settings.r2_public_base_url, object_key)
        if sector.visibility == "public"
        else None
    )
    return UploadUrlResponse(
        upload_url=upload_url,
        object_key=object_key,
        visibility=sector.visibility,
        content_type=content_type,
        public_url=public_url,
    )
