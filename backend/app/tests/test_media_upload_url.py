"""POST /v1/media/upload-url — the presigned client-upload primitive
(INFRA_UPGRADE Phase 1B · COMMIT 3). Gated by STORAGE_WRITES; visibility is set
server-side from the sector.
"""

from __future__ import annotations

import time

import jwt
import pytest
from fastapi.testclient import TestClient

import app.routers.v1.media as media_mod
from app.core.config import get_settings
from app.main import app

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
client = TestClient(app)


def _token() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "sub": "user-123",
            "aud": "authenticated",
            "email": "a@b.com",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


@pytest.fixture
def _gate_on(monkeypatch: pytest.MonkeyPatch):
    """Flip the write-gate on with real-looking R2 config + a fake presigner."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    monkeypatch.setenv("STORAGE_WRITES", "r2")
    monkeypatch.setenv("R2_ENDPOINT", "https://acct.r2.cloudflarestorage.com")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "ak")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "sk")
    monkeypatch.setenv("R2_PUBLIC_BASE_URL", "https://cdn.example.com")
    get_settings.cache_clear()

    class _FakePresigner:
        async def presign_put(self, *, object_key, visibility, content_type):
            return f"https://put.example/{object_key}?ct={content_type}&vis={visibility}"

    monkeypatch.setattr(media_mod, "get_storage_provider", lambda: _FakePresigner())
    yield
    get_settings.cache_clear()


@pytest.fixture
def _gate_off(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    monkeypatch.setenv("STORAGE_WRITES", "legacy")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_requires_token() -> None:
    assert client.post("/v1/media/upload-url", json={}).status_code == 401


def test_gate_off_returns_503(_gate_off) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "wardrobe", "content_type": "image/jpeg", "byte_size": 1000},
        headers=_auth(),
    )
    assert resp.status_code == 503
    assert resp.json()["error"]["code"] == "PROVIDER_ERROR"


def test_private_sector_returns_key_no_public_url(_gate_on) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "wardrobe", "content_type": "image/jpeg", "byte_size": 1000},
        headers=_auth(),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["visibility"] == "private"
    assert body["object_key"].startswith("user-123/wardrobe/")
    assert body["object_key"].endswith(".jpg")
    assert body["public_url"] is None
    assert body["upload_url"].startswith("https://put.example/user-123/wardrobe/")


def test_public_sector_returns_public_url(_gate_on) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "post", "content_type": "image/webp", "byte_size": 2048},
        headers=_auth(),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["visibility"] == "public"
    assert body["object_key"].startswith("user-123/post/")
    assert body["public_url"] == f"https://cdn.example.com/{body['object_key']}"


def test_unknown_sector_rejected(_gate_on) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "secrets", "content_type": "image/jpeg", "byte_size": 10},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_bad_content_type_rejected(_gate_on) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "post", "content_type": "application/pdf", "byte_size": 10},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_oversize_rejected(_gate_on) -> None:
    resp = client.post(
        "/v1/media/upload-url",
        json={"sector": "post", "content_type": "image/jpeg", "byte_size": 99_000_000},
        headers=_auth(),
    )
    assert resp.status_code == 422
