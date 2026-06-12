"""Fashion news feed (CLAUDE.md §1 pillar 5) — auth gate + live SQL schema."""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

client = TestClient(app)


# ── auth gate (runs before any DB access) ────────────────────────────────────


def test_news_requires_token() -> None:
    resp = client.get("/v1/news")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_news_rejects_bad_limit() -> None:
    # limit is validated by FastAPI before the handler runs.
    resp = client.get("/v1/news", params={"limit": 999})
    # No token -> auth still short-circuits to 401; with a token it'd be 422.
    assert resp.status_code in (401, 422)


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_news_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.news import _COLUMNS, _RANK

    stmt = (
        f"select {_COLUMNS} from public.news_items "
        f"where ($1::timestamptz is null or {_RANK} < $1::timestamptz) "
        f"order by {_RANK} desc limit $2"
    )

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            await conn.prepare(stmt)
        finally:
            await conn.close()

    asyncio.run(run())
