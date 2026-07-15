"""Notifications feed — auth gates, validation, live SQL schema."""

from __future__ import annotations

import asyncio
import time
import uuid

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


def test_list_requires_token() -> None:
    assert client.get("/v1/notifications").status_code == 401


def test_mark_read_requires_token() -> None:
    assert client.post(f"/v1/notifications/{uuid.uuid4()}/read").status_code == 401


def test_mark_all_requires_token() -> None:
    assert client.post("/v1/notifications/read-all").status_code == 401


def test_mark_read_rejects_non_uuid() -> None:
    assert client.post("/v1/notifications/not-a-uuid/read", headers=_auth()).status_code == 422


def test_list_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/notifications", headers=_auth())
    assert resp.status_code not in (401, 422)


def test_unread_count_requires_token() -> None:
    assert client.get("/v1/notifications/unread-count").status_code == 401


def test_unread_count_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/notifications/unread-count", headers=_auth())
    assert resp.status_code not in (401, 422)


def test_preferences_get_requires_token() -> None:
    assert client.get("/v1/notifications/preferences").status_code == 401


def test_preferences_patch_requires_token() -> None:
    resp = client.patch(
        "/v1/notifications/preferences", json={"social_activity": False}
    )
    assert resp.status_code == 401


def test_preferences_patch_rejects_non_bool() -> None:
    resp = client.patch(
        "/v1/notifications/preferences",
        json={"social_activity": [1, 2, 3]},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_preferences_patch_rejects_unknown_field() -> None:
    # extra=forbid → an arbitrary/undocumented field is a 422, not silently kept.
    resp = client.patch(
        "/v1/notifications/preferences",
        json={"not_a_category": True},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_notifications_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.notifications import _SELECT

    stmts = [
        _SELECT + " where user_id = $1::uuid order by created_at desc limit $2",
        "update public.notifications set is_read = true "
        "where id = $1::uuid and user_id = $2::uuid returning id",
        "update public.notifications set is_read = true "
        "where user_id = $1::uuid and is_read = false",
        "select count(*) from public.notifications "
        "where user_id = $1::uuid and is_read = false",
        "select account_updates, referral_rewards, social_activity, community, "
        "daily_style, product_updates, promotional "
        "from public.notification_preferences where user_id = $1::uuid",
        "insert into public.notification_preferences (user_id, social_activity) "
        "values ($1::uuid, $2) on conflict (user_id) do update set "
        "social_activity = excluded.social_activity, updated_at = now() "
        "returning account_updates, referral_rewards, social_activity, community, "
        "daily_style, product_updates, promotional",
        # create_notification insert (app.services.notifications)
        "insert into public.notifications "
        "(user_id, actor_id, type, title, body, target_type, target_id) "
        "values ($1::uuid, $2::uuid, $3, $4, $5, $6, $7)",
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
