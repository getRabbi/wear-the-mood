import asyncio
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.profile import BodyData
from app.routers.v1.profile import _CONSENT_EXISTS, _SELECT

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


def test_get_requires_token() -> None:
    resp = client.get("/v1/profile")
    assert resp.status_code == 401


def test_patch_requires_token() -> None:
    resp = client.patch("/v1/profile", json={"display_name": "Sam"})
    assert resp.status_code == 401


def test_patch_rejects_out_of_range_height() -> None:
    resp = client.patch("/v1/profile", json={"body_data": {"height_cm": 5}}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_get_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/profile", headers=_auth())
    assert resp.status_code not in (401, 422)


def test_body_data_model_bounds() -> None:
    assert BodyData(height_cm=175).height_cm == 175
    with pytest.raises(ValueError):
        BodyData(height_cm=10)


def test_profile_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        _SELECT,
        _CONSENT_EXISTS,
        "update public.profiles set display_name = coalesce($2, display_name), "
        "avatar_url = coalesce($3, avatar_url), body_data = coalesce($4::jsonb, body_data), "
        "updated_at = now() where id = $1::uuid "
        "returning id, display_name, avatar_url, body_data, timezone, onboarding_completed",
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
