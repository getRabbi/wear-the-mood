"""Unit tests for the R2 storage provider + the per-record URL resolver
(INFRA_UPGRADE Phase 1B · COMMIT 2).

Hermetic: the pure helpers need no network, and the network methods run against a
fake S3 client injected via the ``_client`` seam — so neither aioboto3 nor real
R2 creds are required. Pillow-dependent thumbnail tests skip if Pillow is absent
(it ships with the worker, not the api/CI base deps).
"""

from __future__ import annotations

import asyncio
import hashlib

import pytest

from app.core.config import Settings
from app.services import media
from app.services.media import legacy as legacy_mod
from app.services.media.r2 import (
    R2StorageProvider,
    build_object_key,
    content_hash,
    ext_for,
    public_url_for,
)


def _settings(**over: object) -> Settings:
    base: dict[str, object] = {
        "environment": "staging",
        "r2_endpoint": "https://acct.r2.cloudflarestorage.com",
        "r2_access_key_id": "ak",
        "r2_secret_access_key": "sk",
        "r2_public_bucket": "prod-public",
        "r2_private_bucket": "prod-private",
        "r2_public_bucket_staging": "stg-public",
        "r2_private_bucket_staging": "stg-private",
        "r2_public_base_url": "https://cdn.example.com",
        "r2_signed_url_ttl": 900,
    }
    base.update(over)
    return Settings(_env_file=None, **base)  # type: ignore[arg-type]


class _FakeS3:
    """Async-context-manager stand-in for the aioboto3 S3 client."""

    def __init__(self) -> None:
        self.put_calls: list[dict[str, object]] = []
        self.delete_calls: list[dict[str, object]] = []
        self.presign_args: tuple[object, ...] | None = None

    async def __aenter__(self) -> _FakeS3:
        return self

    async def __aexit__(self, *exc: object) -> bool:
        return False

    async def put_object(self, **kw: object) -> None:
        self.put_calls.append(kw)

    async def delete_object(self, **kw: object) -> None:
        self.delete_calls.append(kw)

    async def generate_presigned_url(self, op: str, Params: dict, ExpiresIn: int) -> str:
        self.presign_args = (op, Params, ExpiresIn)
        return f"https://signed.example/{Params['Key']}?exp={ExpiresIn}"


def _provider_with_fake(**over: object) -> tuple[R2StorageProvider, _FakeS3]:
    provider = R2StorageProvider(_settings(**over))
    fake = _FakeS3()
    provider._client = lambda: fake  # type: ignore[method-assign]
    return provider, fake


# ── pure helpers ────────────────────────────────────────────────────────────
def test_content_hash_is_stable_sha256() -> None:
    assert content_hash(b"abc") == hashlib.sha256(b"abc").hexdigest()


def test_ext_for_known_and_unknown() -> None:
    assert ext_for("image/jpeg") == ".jpg"
    assert ext_for("image/png") == ".png"
    assert ext_for("image/webp") == ".webp"
    assert ext_for("image/jpeg; charset=binary") == ".jpg"  # params stripped
    assert ext_for("application/octet-stream") == ".bin"


def test_build_object_key_public_is_immutable_private_is_random() -> None:
    pub = build_object_key("u1", "image/png", immutable_hash="deadbeef")
    assert pub == "u1/deadbeef.png"
    a = build_object_key("u1", "image/png", immutable_hash=None)
    b = build_object_key("u1", "image/png", immutable_hash=None)
    assert a != b and a.startswith("u1/") and a.endswith(".png")


def test_public_url_for_joins_cleanly() -> None:
    assert (
        public_url_for("https://cdn.example.com/", "/u1/x.jpg")
        == "https://cdn.example.com/u1/x.jpg"
    )


# ── bucket selection by environment ─────────────────────────────────────────
def test_active_buckets_isolate_prod_from_staging() -> None:
    staging = _settings(environment="staging")
    assert staging.active_public_bucket == "stg-public"
    assert staging.active_private_bucket == "stg-private"
    prod = _settings(environment="prod")
    assert prod.active_public_bucket == "prod-public"
    assert prod.active_private_bucket == "prod-private"


def test_bucket_for_visibility() -> None:
    provider, _ = _provider_with_fake()
    assert provider.bucket_for("public") == "stg-public"
    assert provider.bucket_for("private") == "stg-private"


# ── PUT ─────────────────────────────────────────────────────────────────────
def test_put_public_returns_cdn_url_and_long_cache() -> None:
    provider, fake = _provider_with_fake()
    data = b"hello-bytes"
    stored = asyncio.run(
        provider.put(data, visibility="public", prefix="u1", content_type="image/jpeg")
    )
    digest = hashlib.sha256(data).hexdigest()
    assert stored.bucket == "stg-public"
    assert stored.object_key == f"u1/{digest}.jpg"
    assert stored.public_url == f"https://cdn.example.com/u1/{digest}.jpg"
    assert stored.thumbnail_key is None
    assert len(fake.put_calls) == 1
    assert fake.put_calls[0]["Bucket"] == "stg-public"
    assert fake.put_calls[0]["CacheControl"]  # immutable long-cache for public


def test_put_private_never_yields_public_url() -> None:
    provider, fake = _provider_with_fake()
    stored = asyncio.run(
        provider.put(b"x", visibility="private", prefix="u1", content_type="image/png")
    )
    assert stored.bucket == "stg-private"
    assert stored.public_url is None
    assert stored.object_key.startswith("u1/") and stored.object_key.endswith(".png")
    assert "CacheControl" not in fake.put_calls[0]  # private is not cached


# ── view_url ────────────────────────────────────────────────────────────────
def test_view_url_public_uses_public_url_without_network() -> None:
    provider, fake = _provider_with_fake()
    url = asyncio.run(
        provider.view_url(
            object_key="u1/x.jpg", visibility="public", public_url="https://cdn/x.jpg"
        )
    )
    assert url == "https://cdn/x.jpg"
    assert fake.presign_args is None  # no client call for public


def test_view_url_private_signs_with_ttl() -> None:
    provider, fake = _provider_with_fake()
    url = asyncio.run(
        provider.view_url(object_key="u1/secret.png", visibility="private")
    )
    assert url == "https://signed.example/u1/secret.png?exp=900"
    assert fake.presign_args is not None
    assert fake.presign_args[2] == 900  # ExpiresIn = r2_signed_url_ttl


# ── delete ──────────────────────────────────────────────────────────────────
def test_delete_removes_object_and_thumbnail() -> None:
    provider, fake = _provider_with_fake()
    asyncio.run(
        provider.delete(
            object_key="u1/a.jpg", visibility="private", thumbnail_key="u1/thumb/a.webp"
        )
    )
    keys = {c["Key"] for c in fake.delete_calls}
    assert keys == {"u1/a.jpg", "u1/thumb/a.webp"}


# ── resolver (mixed legacy/r2; point A) ─────────────────────────────────────
def test_resolve_r2_public_returns_public_url() -> None:
    url = asyncio.run(
        media.resolve_view_url(
            storage_provider="r2",
            visibility="public",
            owner_kind="post",
            role="post",
            object_key="u1/x.jpg",
            public_url="https://cdn/x.jpg",
        )
    )
    assert url == "https://cdn/x.jpg"


def test_resolve_legacy_public_passthrough() -> None:
    url = asyncio.run(
        media.resolve_view_url(
            storage_provider="legacy",
            visibility="public",
            owner_kind="post",
            role="post",
            legacy_url="https://supabase/post.jpg",
        )
    )
    assert url == "https://supabase/post.jpg"


def test_resolve_legacy_private_http_wardrobe_is_passthrough() -> None:
    # Wardrobe is classified private but still lives in the public Supabase bucket
    # mid-migration: a full http legacy_url is served as-is until 1C moves bytes.
    url = asyncio.run(
        media.resolve_view_url(
            storage_provider="legacy",
            visibility="private",
            owner_kind="wardrobe_item",
            role="original",
            legacy_url="https://supabase/public/wardrobe/u1/x.jpg",
        )
    )
    assert url == "https://supabase/public/wardrobe/u1/x.jpg"


def test_resolve_legacy_private_path_signs_correct_bucket(monkeypatch) -> None:
    seen: dict[str, object] = {}

    async def fake_sign(bucket: str, path: str, expires_in: int = 3600) -> str:
        seen.update(bucket=bucket, path=path, ttl=expires_in)
        return f"signed://{bucket}/{path}?e={expires_in}"

    monkeypatch.setattr(legacy_mod, "create_signed_url", fake_sign)
    url = asyncio.run(
        media.resolve_view_url(
            storage_provider="legacy",
            visibility="private",
            owner_kind="tryon_result",
            role="result",
            legacy_url="u1/result/abc.png",  # a bare path → must be signed
            ttl=120,
        )
    )
    assert seen["bucket"] == "tryon-results"  # mapped from (owner_kind, role)
    assert seen["path"] == "u1/result/abc.png"
    assert url == "signed://tryon-results/u1/result/abc.png?e=120"


# ── thumbnails (Pillow — worker dep; skip if absent) ────────────────────────
def test_make_thumbnail_webp_downscales() -> None:
    Image = pytest.importorskip("PIL.Image")
    from app.services.media.r2 import make_thumbnail_webp

    buf_src = Image.new("RGB", (2000, 1000), (200, 100, 50))
    import io

    raw = io.BytesIO()
    buf_src.save(raw, format="PNG")
    thumb_bytes = make_thumbnail_webp(raw.getvalue(), max_edge=256)

    out = Image.open(io.BytesIO(thumb_bytes))
    assert out.format == "WEBP"
    assert max(out.size) <= 256


def test_put_with_thumbnail_stores_two_objects() -> None:
    pytest.importorskip("PIL.Image")
    from PIL import Image

    provider, fake = _provider_with_fake()
    import io

    raw = io.BytesIO()
    Image.new("RGB", (800, 800), (10, 20, 30)).save(raw, format="PNG")
    stored = asyncio.run(
        provider.put(
            raw.getvalue(),
            visibility="private",
            prefix="u1",
            content_type="image/png",
            make_thumbnail=True,
        )
    )
    assert stored.thumbnail_key is not None
    assert stored.thumbnail_key.startswith("u1/thumb/")
    assert stored.thumbnail_key.endswith(".webp")
    assert len(fake.put_calls) == 2  # original + thumbnail
