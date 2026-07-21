"""freshen_media_url / classify_url — re-signing expiring first-party try-on URLs.

Regression guard for the "That image couldn't be read" try-on failure: the app
submits a signed URL minted an hour earlier at closet-load time; by submit it has
expired and moderation (then FASHN) can't download it. These prove we re-sign a
FRESH URL from the same object key/path, and pass everything else through.
"""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest

import app.services.media.refresh as refresh
from app.services.media.refresh import classify_url

PRIV = "fashionos-private"

# A real-shape expired R2 presigned GET (the exact failure from production logs).
R2_EXPIRED = (
    "https://5c06252f18014fafe3ceed6acd45e82a.r2.cloudflarestorage.com/"
    "fashionos-private/ad8729c3-ebe1-4c0b-b343-ca1fa3a6107c/wardrobe_item/"
    "f89cdbf7cd8d4cb4a7bee432ac0622f4.png?X-Amz-Algorithm=AWS4-HMAC-SHA256"
    "&X-Amz-Date=20260721T042804Z&X-Amz-Expires=3600&X-Amz-Signature=dead"
)
SUPA_SIGNED = (
    "https://ghzabbceoaoertatkjyg.supabase.co/storage/v1/object/sign/avatars/"
    "ad8729c3-ebe1-4c0b-b343-ca1fa3a6107c/tryon/1784612521376661.jpg?token=old.jwt.here"
)
R2_PUBLIC_CDN = "https://cdn.wearthemood.com/studio-models/e089591e.png"
SUPA_PUBLIC = (
    "https://ghzabbceoaoertatkjyg.supabase.co/storage/v1/object/public/"
    "wardrobe/ad8729c3/cutout/7cea2d13.png"
)
THIRD_PARTY = "https://picsum.photos/seed/fos-linen/600/800"


# ── classify_url (pure) ──────────────────────────────────────────────────────


def test_classify_r2_private_extracts_key() -> None:
    ref = classify_url(R2_EXPIRED, private_bucket=PRIV)
    assert ref is not None and ref.scheme == "r2_private"
    assert ref.object_key == (
        "ad8729c3-ebe1-4c0b-b343-ca1fa3a6107c/wardrobe_item/f89cdbf7cd8d4cb4a7bee432ac0622f4.png"
    )


def test_classify_supabase_sign_extracts_bucket_and_path() -> None:
    ref = classify_url(SUPA_SIGNED, private_bucket=PRIV)
    assert ref is not None and ref.scheme == "supabase_sign"
    assert ref.bucket == "avatars"
    assert ref.object_key == "ad8729c3-ebe1-4c0b-b343-ca1fa3a6107c/tryon/1784612521376661.jpg"


@pytest.mark.parametrize("url", [R2_PUBLIC_CDN, SUPA_PUBLIC, THIRD_PARTY, "", "not-a-url", None])
def test_classify_passthrough_returns_none(url) -> None:
    assert classify_url(url, private_bucket=PRIV) is None


def test_classify_r2_wrong_bucket_is_passthrough() -> None:
    # A PUBLIC R2 bucket presigned URL must not be treated as private.
    url = R2_EXPIRED.replace("/fashionos-private/", "/fashionos-public/")
    assert classify_url(url, private_bucket=PRIV) is None


# ── freshen_media_url (async, faked signers) ─────────────────────────────────


class _FakeR2:
    async def view_url(self, *, object_key: str, visibility: str, public_url=None) -> str:
        assert visibility == "private"
        return f"https://fresh.r2/{object_key}?X-Amz-Date=NOW&sig=fresh"


def _patch(monkeypatch, *, r2=None, sign=None, priv=PRIV):
    monkeypatch.setattr(
        refresh, "get_settings", lambda: SimpleNamespace(active_private_bucket=priv)
    )
    monkeypatch.setattr(refresh, "get_storage_provider", lambda: r2 or _FakeR2())
    if sign is not None:
        monkeypatch.setattr(refresh, "create_signed_url", sign)


def test_expired_r2_url_is_resigned_fresh(monkeypatch) -> None:
    _patch(monkeypatch)
    out = asyncio.run(refresh.freshen_media_url(R2_EXPIRED))
    assert out.startswith("https://fresh.r2/")
    assert "wardrobe_item/f89cdbf7" in out
    assert "20260721T042804Z" not in out  # the stale signature is gone


def test_supabase_signed_url_is_resigned_fresh(monkeypatch) -> None:
    async def fake_sign(bucket: str, path: str) -> str:
        return f"https://fresh.supa/{bucket}/{path}?token=fresh"

    _patch(monkeypatch, sign=fake_sign)
    out = asyncio.run(refresh.freshen_media_url(SUPA_SIGNED))
    assert out == (
        "https://fresh.supa/avatars/"
        "ad8729c3-ebe1-4c0b-b343-ca1fa3a6107c/tryon/1784612521376661.jpg?token=fresh"
    )


@pytest.mark.parametrize("url", [R2_PUBLIC_CDN, SUPA_PUBLIC, THIRD_PARTY])
def test_passthrough_urls_unchanged(monkeypatch, url) -> None:
    _patch(monkeypatch)
    assert asyncio.run(refresh.freshen_media_url(url)) == url


def test_signer_failure_passes_original_through(monkeypatch) -> None:
    class _Boom:
        async def view_url(self, **_kw):
            raise RuntimeError("R2 down")

    _patch(monkeypatch, r2=_Boom())
    # Never raises; returns the original so existing moderation still runs.
    assert asyncio.run(refresh.freshen_media_url(R2_EXPIRED)) == R2_EXPIRED
