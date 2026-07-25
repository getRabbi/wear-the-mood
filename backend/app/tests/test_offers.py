"""Daily Offers — auth gate, affiliate attribution, live SQL schema."""

from __future__ import annotations

import asyncio
import time
from urllib.parse import parse_qs, urlparse

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.routers.v1.offers import _attributed

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token() -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "sub": "u1",
            "aud": "authenticated",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )


def test_offers_today_requires_token() -> None:
    assert client.get("/v1/offers/today").status_code == 401


def test_offers_today_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/offers/today", headers={"Authorization": f"Bearer {_token()}"})
    assert resp.status_code not in (401, 422)


def test_attribution_added_and_existing_query_preserved() -> None:
    tagged = _attributed("https://shop.example.com/p")
    q = parse_qs(urlparse(tagged).query)
    assert q["utm_source"] == ["fashionos"]
    assert q["utm_medium"] == ["app"]

    tagged2 = _attributed("https://shop.example.com/p?sku=42")
    q2 = parse_qs(urlparse(tagged2).query)
    assert q2["sku"] == ["42"]  # partner's own param preserved
    assert q2["utm_source"] == ["fashionos"]


def test_offers_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            await conn.prepare(
                "select id, title, brand, image_url, discount_label, affiliate_url, "
                "topics from public.offers where is_active "
                "and (valid_from is null or valid_from <= now()) "
                "and (valid_to is null or valid_to >= now()) order by created_at desc"
            )
        finally:
            await conn.close()

    asyncio.run(run())
