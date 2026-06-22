"""StorageProvider — unified image object interface (CLAUDE.md §8;
INFRA_UPGRADE Phase 1B · COMMIT 2).

Every NEW image write/serve goes through this interface so the storage backend
(Cloudflare R2 public/private buckets, with the legacy Supabase store as a
fallback for not-yet-migrated objects) is swappable and roll-back-able. The
concrete provider is chosen by env in ``app.services.media.get_storage_provider``
— mirrors the TryOnProvider / BackgroundRemover pattern (never call a vendor SDK
from a router or worker directly).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Literal

Visibility = Literal["public", "private"]


@dataclass(frozen=True)
class StoredObject:
    """Result of a PUT — exactly what the caller persists on a media_assets row."""

    object_key: str
    bucket: str
    visibility: Visibility
    content_hash: str
    public_url: str | None = None  # set ONLY for public objects (stable CDN URL)
    thumbnail_key: str | None = None  # set when a thumbnail was generated


class StorageProvider(ABC):
    name: str

    @abstractmethod
    async def put(
        self,
        data: bytes,
        *,
        visibility: Visibility,
        prefix: str,
        content_type: str,
        make_thumbnail: bool = False,
    ) -> StoredObject:
        """Store ``data`` in the bucket for ``visibility``; optionally generate +
        store a thumbnail in the SAME bucket. Public → returns a stable CDN
        ``public_url``; private → returns ``object_key`` only and NEVER a public
        URL (the caller serves it via :meth:`view_url`)."""
        raise NotImplementedError

    @abstractmethod
    async def view_url(
        self,
        *,
        object_key: str,
        visibility: Visibility,
        public_url: str | None = None,
    ) -> str:
        """Resolve a viewable URL. Public → the stable ``public_url``. Private → a
        SHORT-LIVED signed URL that expires (must NOT be cached in a shared/public
        CDN, §8)."""
        raise NotImplementedError

    @abstractmethod
    async def delete(
        self,
        *,
        object_key: str,
        visibility: Visibility,
        thumbnail_key: str | None = None,
    ) -> None:
        """Remove an object (and its thumbnail) — used by the Phase 4A deletion
        sweep after the retention window."""
        raise NotImplementedError
