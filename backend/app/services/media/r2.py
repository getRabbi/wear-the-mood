"""Cloudflare R2 storage provider over the S3 API (aioboto3) — CLAUDE.md §2, §8.

Keys/creds are backend-only (§11). Buckets are environment-isolated (prod vs the
*_STAGING buckets) via ``Settings.active_*_bucket``. Public objects get immutable
content-hash keys + a stable CDN URL (long-cache); private objects get
unguessable keys and are served ONLY through short-lived signed URLs
(``R2_SIGNED_URL_TTL``).

``aioboto3`` and ``Pillow`` are LAZY-imported — aioboto3 only inside the network
methods, Pillow only when a thumbnail is actually generated (Pillow ships with
the worker, which does the thumbnailing) — so the api can import this module
without pulling either, and the pure helpers below stay unit-testable offline.
"""

from __future__ import annotations

import hashlib
import io
from uuid import uuid4

from app.core.config import Settings
from app.services.media.base import StorageProvider, StoredObject, Visibility

# Content-type → extension. Unknown types fall back to .bin (validated upstream).
_EXT = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
# Public objects use immutable content-hash keys, so they can be cached forever.
_LONG_CACHE = "public, max-age=31536000, immutable"
_THUMB_CONTENT_TYPE = "image/webp"


def content_hash(data: bytes) -> str:
    """Stable SHA-256 hex digest — public key + integrity check (1C VERIFY)."""
    return hashlib.sha256(data).hexdigest()


def ext_for(content_type: str) -> str:
    return _EXT.get(content_type.lower().split(";")[0].strip(), ".bin")


def build_object_key(prefix: str, content_type: str, *, immutable_hash: str | None) -> str:
    """``<prefix>/<hash-or-uuid><ext>``. Public passes the content hash (immutable,
    dedupes); private passes None → a random uuid (no caching, unguessable)."""
    name = immutable_hash if immutable_hash else uuid4().hex
    return f"{prefix.strip('/')}/{name}{ext_for(content_type)}"


def public_url_for(base_url: str, object_key: str) -> str:
    return f"{base_url.rstrip('/')}/{object_key.lstrip('/')}"


def make_thumbnail_webp(data: bytes, *, max_edge: int = 512, quality: int = 80) -> bytes:
    """Downscale to a ≤``max_edge`` WebP thumbnail (lazy Pillow — worker dep).
    WebP keeps cutout transparency (RGBA) and is small for feeds/grids (§4, 1D)."""
    from PIL import Image

    img = Image.open(io.BytesIO(data))
    img = img.convert("RGBA") if img.mode in ("RGBA", "LA", "P") else img.convert("RGB")
    img.thumbnail((max_edge, max_edge))
    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=quality, method=6)
    return buf.getvalue()


class R2StorageProvider(StorageProvider):
    name = "r2"

    def __init__(self, settings: Settings) -> None:
        self._endpoint = settings.r2_endpoint
        self._access_key = settings.r2_access_key_id
        self._secret_key = settings.r2_secret_access_key
        self._public_bucket = settings.active_public_bucket
        self._private_bucket = settings.active_private_bucket
        self._base_url = settings.r2_public_base_url
        self._ttl = settings.r2_signed_url_ttl

    def bucket_for(self, visibility: Visibility) -> str:
        return self._public_bucket if visibility == "public" else self._private_bucket

    def _client(self):
        """Async-context-manager S3 client. A SEAM for tests (override the
        instance attribute with a fake) and the only place aioboto3 is imported."""
        import aioboto3

        return aioboto3.Session().client(
            "s3",
            endpoint_url=self._endpoint,
            region_name="auto",
            aws_access_key_id=self._access_key,
            aws_secret_access_key=self._secret_key,
        )

    async def put(
        self,
        data: bytes,
        *,
        visibility: Visibility,
        prefix: str,
        content_type: str,
        make_thumbnail: bool = False,
    ) -> StoredObject:
        digest = content_hash(data)
        is_public = visibility == "public"
        bucket = self.bucket_for(visibility)
        key = build_object_key(
            prefix, content_type, immutable_hash=digest if is_public else None
        )
        cache = {"CacheControl": _LONG_CACHE} if is_public else {}
        thumbnail_key: str | None = None

        async with self._client() as s3:
            await s3.put_object(
                Bucket=bucket, Key=key, Body=data, ContentType=content_type, **cache
            )
            if make_thumbnail:
                thumb = make_thumbnail_webp(data)
                thumbnail_key = build_object_key(
                    f"{prefix.strip('/')}/thumb",
                    _THUMB_CONTENT_TYPE,
                    immutable_hash=content_hash(thumb) if is_public else None,
                )
                await s3.put_object(
                    Bucket=bucket,
                    Key=thumbnail_key,
                    Body=thumb,
                    ContentType=_THUMB_CONTENT_TYPE,
                    **cache,
                )

        return StoredObject(
            object_key=key,
            bucket=bucket,
            visibility=visibility,
            content_hash=digest,
            public_url=public_url_for(self._base_url, key) if is_public else None,
            thumbnail_key=thumbnail_key,
        )

    async def view_url(
        self,
        *,
        object_key: str,
        visibility: Visibility,
        public_url: str | None = None,
    ) -> str:
        if visibility == "public":
            return public_url or public_url_for(self._base_url, object_key)
        async with self._client() as s3:
            return await s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": self._private_bucket, "Key": object_key},
                ExpiresIn=self._ttl,
            )

    async def presign_get_many(self, object_keys: list[str]) -> dict[str, str]:
        """Sign many PRIVATE keys with ONE client — for list/feed responses so the
        client doesn't fetch URLs one-by-one (§8). Public keys never come here."""
        if not object_keys:
            return {}
        async with self._client() as s3:
            out: dict[str, str] = {}
            for key in object_keys:
                out[key] = await s3.generate_presigned_url(
                    "get_object",
                    Params={"Bucket": self._private_bucket, "Key": key},
                    ExpiresIn=self._ttl,
                )
            return out

    async def head(self, *, object_key: str, visibility: Visibility) -> int:
        """ContentLength of a stored object — verifies it actually persisted
        (used by the 1C backfill). Raises if the object is absent."""
        async with self._client() as s3:
            resp = await s3.head_object(
                Bucket=self.bucket_for(visibility), Key=object_key
            )
            return int(resp["ContentLength"])

    async def presign_put(
        self, *, object_key: str, visibility: Visibility, content_type: str
    ) -> str:
        """Mint a one-time PUT URL so the app uploads bytes STRAIGHT to R2 (§8) —
        no proxy, no keys on the client (§11). The bucket is chosen server-side."""
        async with self._client() as s3:
            return await s3.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": self.bucket_for(visibility),
                    "Key": object_key,
                    "ContentType": content_type,
                },
                ExpiresIn=self._ttl,
            )

    async def delete(
        self,
        *,
        object_key: str,
        visibility: Visibility,
        thumbnail_key: str | None = None,
    ) -> None:
        bucket = self.bucket_for(visibility)
        async with self._client() as s3:
            await s3.delete_object(Bucket=bucket, Key=object_key)
            if thumbnail_key:
                await s3.delete_object(Bucket=bucket, Key=thumbnail_key)

    async def delete_prefix(self, *, prefix: str, visibility: Visibility) -> int:
        """Delete EVERY object under ``prefix`` in the bucket for ``visibility``
        (account erasure — Phase 4A). S3 list is recursive, so one prefix sweeps
        all nested keys. Returns the number of objects deleted."""
        bucket = self.bucket_for(visibility)
        deleted = 0
        async with self._client() as s3:
            token: str | None = None
            while True:
                kwargs = {"Bucket": bucket, "Prefix": prefix}
                if token:
                    kwargs["ContinuationToken"] = token
                resp = await s3.list_objects_v2(**kwargs)
                keys = [{"Key": o["Key"]} for o in resp.get("Contents", [])]
                for i in range(0, len(keys), 1000):  # delete_objects caps at 1000
                    await s3.delete_objects(
                        Bucket=bucket, Delete={"Objects": keys[i : i + 1000]}
                    )
                deleted += len(keys)
                if not resp.get("IsTruncated"):
                    break
                token = resp.get("NextContinuationToken")
        return deleted

    async def put_exact(
        self, *, object_key: str, data: bytes, content_type: str, visibility: Visibility
    ) -> None:
        """Upload bytes to an EXACT key (no content-hash key, no thumbnail) — for
        non-image artifacts like DB backups (Phase 4B)."""
        async with self._client() as s3:
            await s3.put_object(
                Bucket=self.bucket_for(visibility),
                Key=object_key,
                Body=data,
                ContentType=content_type,
            )

    async def list_keys(self, *, prefix: str, visibility: Visibility) -> list[str]:
        """Every object key under ``prefix`` (paginated) — for backup pruning."""
        bucket = self.bucket_for(visibility)
        keys: list[str] = []
        async with self._client() as s3:
            token: str | None = None
            while True:
                kwargs = {"Bucket": bucket, "Prefix": prefix}
                if token:
                    kwargs["ContinuationToken"] = token
                resp = await s3.list_objects_v2(**kwargs)
                keys.extend(o["Key"] for o in resp.get("Contents", []))
                if not resp.get("IsTruncated"):
                    break
                token = resp.get("NextContinuationToken")
        return keys
