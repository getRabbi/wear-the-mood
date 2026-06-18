"""Polls under posts — auth gates, model validation, live SQL schema."""

from __future__ import annotations

import asyncio
import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.poll import PollCreate, PollVote

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


def _auth() -> dict:
    return {"Authorization": f"Bearer {_token()}"}


# ── auth gates ───────────────────────────────────────────────────────────────


def test_get_poll_requires_token() -> None:
    assert client.get(f"/v1/polls/{uuid.uuid4()}").status_code == 401


def test_vote_requires_token() -> None:
    resp = client.post(f"/v1/polls/{uuid.uuid4()}/vote", json={"option_index": 0})
    assert resp.status_code == 401


def test_vote_rejects_negative_option() -> None:
    resp = client.post(
        f"/v1/polls/{uuid.uuid4()}/vote",
        json={"option_index": -1},
        headers=_auth(),
    )
    assert resp.status_code == 422


# ── model validation ─────────────────────────────────────────────────────────


def test_poll_requires_two_to_four_options() -> None:
    with pytest.raises(ValueError):
        PollCreate(question="Q", options=["only one"])
    with pytest.raises(ValueError):
        PollCreate(question="Q", options=["a", "b", "c", "d", "e"])
    # blanks are dropped before counting
    with pytest.raises(ValueError):
        PollCreate(question="Q", options=["a", "  ", ""])
    ok = PollCreate(question="Q", options=[" a ", "b", ""])
    assert ok.options == ["a", "b"]


def test_poll_vote_index_non_negative() -> None:
    assert PollVote(option_index=0).option_index == 0
    with pytest.raises(ValueError):
        PollVote(option_index=-2)


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_polls_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.services.polls import _POLL_SELECT

    stmts = [
        _POLL_SELECT + " where pp.post_id = any($2::uuid[])",
        _POLL_SELECT + " where pp.id = $2::uuid",
        "select options, closes_at from public.post_polls where id = $1::uuid",
        "insert into public.poll_votes (poll_id, user_id, option_index) "
        "values ($1::uuid, $2::uuid, $3) on conflict (poll_id, user_id) "
        "do update set option_index = excluded.option_index, created_at = now()",
        "insert into public.post_polls (post_id, question, options, closes_at) "
        "values ($1::uuid, $2, $3::jsonb, $4)",
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
