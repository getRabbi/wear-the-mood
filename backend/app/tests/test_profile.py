import asyncio
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.profile import BodyData, ProfileUpdate
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


def test_body_data_rich_fields_valid() -> None:
    b = BodyData(
        gender="female",
        height_cm=170,
        weight_kg=62,
        age_range="25_34",
        body_type="Hourglass",
        fit_preference="regular",
        skin_tone="medium",
    )
    # exclude_none must drop nothing here and keep every supplied field.
    assert b.model_dump(exclude_none=True)["gender"] == "female"
    assert b.fit_preference == "regular"


def test_body_data_rejects_bad_enums_and_bounds() -> None:
    with pytest.raises(ValueError):
        BodyData(gender="other")  # not in the allowed Literal set
    with pytest.raises(ValueError):
        BodyData(fit_preference="baggy")
    with pytest.raises(ValueError):
        BodyData(weight_kg=5)  # below ge=20


def test_patch_rejects_bad_gender() -> None:
    resp = client.patch("/v1/profile", json={"body_data": {"gender": "robot"}}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_profile_update_cleans_style_tags() -> None:
    # strips '#'/whitespace, drops blanks, de-dupes, caps the count at 8.
    p = ProfileUpdate(style_tags=["#Modest", " minimal ", "minimal", "", "  "])
    assert p.style_tags == ["Modest", "minimal"]
    assert len(ProfileUpdate(style_tags=[f"t{i}" for i in range(20)]).style_tags) == 8
    # None leaves the field unchanged (not cleared).
    assert ProfileUpdate(display_name="Sam").style_tags is None


def test_patch_rejects_overlong_bio() -> None:
    resp = client.patch("/v1/profile", json={"bio": "x" * 301}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_profile_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        _SELECT,
        _CONSENT_EXISTS,
        "update public.profiles set display_name = coalesce($2, display_name), "
        "phone = coalesce($3, phone), "
        "avatar_url = coalesce($4, avatar_url), "
        "profile_picture_url = coalesce($5, profile_picture_url), "
        "body_data = coalesce($6::jsonb, body_data), "
        "bio = coalesce($7, bio), "
        "style_tags = coalesce($8::text[], style_tags), "
        "is_public = coalesce($9, is_public), "
        "updated_at = now() where id = $1::uuid "
        "returning id, display_name, phone, avatar_url, profile_picture_url, "
        "body_data, timezone, onboarding_completed, bio, style_tags, is_public",
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
