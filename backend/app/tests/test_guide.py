"""Daily Guide — auth gate + live SQL schema."""

from __future__ import annotations

import asyncio
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

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
        {"sub": "u1", "aud": "authenticated", "role": "authenticated",
         "iat": now, "exp": now + 3600},
        TEST_SECRET,
        algorithm="HS256",
    )


def test_guide_today_requires_token() -> None:
    assert client.get("/v1/guide/today").status_code == 401


def test_guide_today_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get(
        "/v1/guide/today", headers={"Authorization": f"Bearer {_token()}"}
    )
    assert resp.status_code not in (401, 422)


def test_guide_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            await conn.prepare(
                "select id, date, title, summary, body, image_url, topics, cta, "
                "created_at from public.daily_guides where date <= current_date "
                "order by date desc, created_at desc limit 1"
            )
        finally:
            await conn.close()

    asyncio.run(run())
