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


def test_record_requires_token() -> None:
    resp = client.post("/v1/consents", json={"consent_type": "biometric", "version": "1"})
    assert resp.status_code == 401


def test_record_rejects_missing_fields() -> None:
    resp = client.post("/v1/consents", json={"consent_type": "biometric"}, headers=_auth())
    assert resp.status_code == 422


def test_record_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.post(
        "/v1/consents",
        json={"consent_type": "biometric", "version": "1.0"},
        headers=_auth(),
    )
    assert resp.status_code not in (401, 422)


def test_consents_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmt = (
        "insert into public.consents (user_id, consent_type, version, granted) "
        "values ($1::uuid, $2, $3, true) "
        "returning id, consent_type, version, granted, created_at"
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
