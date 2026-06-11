"""Challenges — auth gates, request validation, live SQL schema (§1 pillar 4)."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.challenge import ChallengeJoin

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


# ── auth gates (run before any DB access) ────────────────────────────────────


def test_list_requires_token() -> None:
    resp = client.get("/v1/challenges")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_get_requires_token() -> None:
    assert client.get("/v1/challenges/monochrome").status_code == 401


def test_join_requires_token() -> None:
    resp = client.post(f"/v1/challenges/{uuid.uuid4()}/join", json={"post_id": str(uuid.uuid4())})
    assert resp.status_code == 401


def test_leave_requires_token() -> None:
    url = f"/v1/challenges/{uuid.uuid4()}/entries/{uuid.uuid4()}"
    assert client.delete(url).status_code == 401


def test_entries_requires_token() -> None:
    assert client.get(f"/v1/challenges/{uuid.uuid4()}/entries").status_code == 401


# ── request validation ───────────────────────────────────────────────────────


def test_join_model_requires_post_id() -> None:
    with pytest.raises(ValueError):
        ChallengeJoin()  # post_id missing
    assert ChallengeJoin(post_id=uuid.uuid4()).post_id is not None


def test_join_body_required() -> None:
    resp = client.post(f"/v1/challenges/{uuid.uuid4()}/join", json={}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_join_rejects_non_uuid_path() -> None:
    resp = client.post(
        "/v1/challenges/not-a-uuid/join",
        json={"post_id": str(uuid.uuid4())},
        headers=_auth(),
    )
    assert resp.status_code == 422


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_challenges_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.challenges import _ACTIVE, _CHALLENGE_SELECT, _ENTRY_SELECT

    stmts = [
        _CHALLENGE_SELECT + f" where {_ACTIVE} order by c.starts_at desc",
        _CHALLENGE_SELECT + " where c.slug = $2",
        _CHALLENGE_SELECT + " where c.id = $2::uuid",
        f"select 1 from public.challenges c where id = $1::uuid and {_ACTIVE}",
        "select 1 from public.posts where id = $1::uuid and user_id = $2::uuid",
        "insert into public.challenge_entries (challenge_id, post_id, user_id) "
        "values ($1::uuid, $2::uuid, $3::uuid) on conflict (challenge_id, post_id) do nothing",
        "delete from public.challenge_entries "
        "where challenge_id = $1::uuid and post_id = $2::uuid and user_id = $3::uuid",
        _ENTRY_SELECT + " where e.challenge_id = $2::uuid and ($3::timestamptz is null or "
        "e.created_at < $3::timestamptz) and not exists (select 1 from public.blocks b "
        "where (b.blocker_id = $1::uuid and b.blocked_id = e.user_id) or "
        "(b.blocker_id = e.user_id and b.blocked_id = $1::uuid)) "
        "order by e.created_at desc limit $4",
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
