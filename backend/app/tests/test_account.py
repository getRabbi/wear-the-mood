import asyncio
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.routers.v1.account import _EXPORT_QUERIES, _PROFILE_QUERY

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
    payload = {
        "sub": "user-123",
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


# ── auth gates (run before any DB access) ────────────────────────────────────


def test_export_requires_token() -> None:
    resp = client.get("/v1/account/export")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_delete_requires_token() -> None:
    resp = client.delete("/v1/account")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_export_authed_reaches_db_layer() -> None:
    # A valid token gets past auth into the DB layer (500 only because the test
    # harness starts no pool) — proves the route exists and is authed, not gated.
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/account/export", headers=_auth())
    assert resp.status_code not in (401, 404)


# ── live schema validation (skips without a DSN; prepare-only, never mutates) ─


def test_account_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [_PROFILE_QUERY, *(sql for _, sql in _EXPORT_QUERIES)]
    # Deletion statements: prepare validates shape/columns (never executed here).
    stmts += [
        "delete from public.idempotency_keys where user_id = $1::uuid",
        "update public.ai_usage_log set user_id = null where user_id = $1::uuid",
        "delete from auth.users where id = $1::uuid",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())


def test_export_covers_every_user_owned_table() -> None:
    # Guard against forgetting a table in the export when the schema grows.
    exported = {key for key, _ in _EXPORT_QUERIES}
    expected = {
        "credits",
        "wardrobe_items",
        "outfits",
        "tryon_jobs",
        "tryon_results",
        "taste_signals",
        "consents",
        "posts",
        "follows",
        "likes",
        "comments",
        "reports",
    }
    assert exported == expected
