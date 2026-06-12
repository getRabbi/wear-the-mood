"""Shop-the-look affiliate links (CLAUDE.md §18, §24) — builder, resolver, endpoint."""

from __future__ import annotations

import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.shop import ShopLinkBuilder, get_shop_builder

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _clear_cache(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    get_shop_builder.cache_clear()
    yield
    get_settings.cache_clear()
    get_shop_builder.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": "user-123",
            "aud": "authenticated",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


# ── builder ──────────────────────────────────────────────────────────────────


def test_builder_encodes_query_without_tag() -> None:
    b = ShopLinkBuilder(name="stub", search_url="https://www.google.com/search")
    link = b.build("beige trench coat", label="Shop this trend")
    assert link.url == "https://www.google.com/search?q=beige+trench+coat"
    assert link.label == "Shop this trend"
    assert "tag" not in link.url


def test_builder_appends_affiliate_tag_when_set() -> None:
    b = ShopLinkBuilder(
        name="acme",
        search_url="https://shop.example.com/s",
        query_param="query",
        tag_param="aff",
        tag="fashionos-21",
    )
    link = b.build("blue jeans", label="Shop")
    assert "query=blue+jeans" in link.url
    assert "aff=fashionos-21" in link.url


# ── resolver ─────────────────────────────────────────────────────────────────


def test_default_builder_is_stub_web_search(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AFFILIATE_SEARCH_URL", "")
    get_settings.cache_clear()
    get_shop_builder.cache_clear()
    assert get_shop_builder().name == "stub"


def test_configured_builder_uses_affiliate(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AFFILIATE_PROVIDER", "acme")
    monkeypatch.setenv("AFFILIATE_SEARCH_URL", "https://shop.example.com/s")
    monkeypatch.setenv("AFFILIATE_TAG_PARAM", "aff")
    monkeypatch.setenv("AFFILIATE_TAG", "fashionos-21")
    get_settings.cache_clear()
    get_shop_builder.cache_clear()
    link = get_shop_builder().build("coat", label="Shop")
    assert "shop.example.com" in link.url and "aff=fashionos-21" in link.url


# ── endpoint ─────────────────────────────────────────────────────────────────


def test_shop_link_requires_token() -> None:
    resp = client.get("/v1/shop/link", params={"q": "trench"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_shop_link_returns_a_link(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("AFFILIATE_SEARCH_URL", "")  # stub web search
    get_settings.cache_clear()
    get_shop_builder.cache_clear()
    resp = client.get("/v1/shop/link", params={"q": "trench coat"}, headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert "trench+coat" in body["url"]
    assert body["query"] == "trench coat"


def test_shop_link_requires_q() -> None:
    resp = client.get("/v1/shop/link", headers=_auth())
    assert resp.status_code == 422
