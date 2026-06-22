"""Media storage package (CLAUDE.md §8; INFRA_UPGRADE Phase 1B · COMMIT 2).

Public surface:
  * ``get_storage_provider()`` — the active object-storage provider (R2 over S3),
    used for ALL new writes once the upload paths are wired (Commit 3).
  * ``resolve_view_url(...)`` — turn one media_assets row into a viewable URL,
    dispatching per-record between the legacy Supabase store and R2 so a mixed
    (mid-migration) closet/feed never breaks (INFRA_UPGRADE point A).

Nothing here is on a live request path yet — Commit 3 wires it into the upload
endpoints and the closet/feed serving.
"""

from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings
from app.services.media.base import StorageProvider, StoredObject, Visibility
from app.services.media.legacy import LEGACY_PRIVATE_BUCKET, legacy_private_view_url
from app.services.media.r2 import R2StorageProvider

__all__ = [
    "StorageProvider",
    "StoredObject",
    "Visibility",
    "R2StorageProvider",
    "get_storage_provider",
    "resolve_view_url",
]


@lru_cache
def get_storage_provider() -> StorageProvider:
    """Active object-storage provider for NEW writes (CLAUDE.md §8). R2 over the
    S3 API; creds are backend-only (§11)."""
    return R2StorageProvider(get_settings())


async def resolve_view_url(
    *,
    storage_provider: str,
    visibility: Visibility,
    owner_kind: str,
    role: str,
    object_key: str | None = None,
    public_url: str | None = None,
    legacy_url: str | None = None,
    ttl: int | None = None,
) -> str | None:
    """Resolve a media_assets row to a viewable URL, PER-RECORD.

    r2     → public: the stored public_url; private: a fresh signed R2 URL.
    legacy → public (or a full http URL): the legacy_url unchanged; private path:
             a signed Supabase URL via the bucket mapped from (owner_kind, role).
    """
    if storage_provider == "r2":
        if object_key is None:
            return public_url
        return await get_storage_provider().view_url(
            object_key=object_key, visibility=visibility, public_url=public_url
        )

    # legacy
    if visibility == "public" or (legacy_url or "").startswith("http"):
        return legacy_url
    bucket = LEGACY_PRIVATE_BUCKET.get((owner_kind, role))
    if not bucket or not legacy_url:
        return legacy_url
    return await legacy_private_view_url(
        bucket, legacy_url, ttl or get_settings().r2_signed_url_ttl
    )
