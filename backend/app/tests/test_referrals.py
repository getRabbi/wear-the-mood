"""Referral loop (CLAUDE.md §24) — code gen, redemption rules, endpoints, live SQL."""

from __future__ import annotations

import asyncio
import time

import asyncpg
import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.errors import ApiError
from app.main import app
from app.services.referrals import _ALPHABET, gen_code, redeem

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _secret(monkeypatch: pytest.MonkeyPatch):
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


class _FakeTx:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _FakeConn:
    """Supports the transaction()/fetchval/execute that redeem() needs."""

    def __init__(self, *, referrer_id=None, dup=False) -> None:
        self._referrer_id = referrer_id
        self._dup = dup
        self.executed: list[str] = []

    def transaction(self):
        return _FakeTx()

    async def fetchval(self, sql: str, *args):
        return self._referrer_id  # the referral_code -> referrer lookup

    async def execute(self, sql: str, *args):
        if self._dup and "insert into public.referrals" in sql:
            raise asyncpg.UniqueViolationError("already referred")
        self.executed.append(sql)


# ── code generation ──────────────────────────────────────────────────────────


def test_gen_code_is_eight_unambiguous_chars() -> None:
    code = gen_code()
    assert len(code) == 8
    assert all(ch in _ALPHABET for ch in code)
    assert not (set("O0I1") & set(code))  # ambiguous chars excluded


# ── redemption rules ─────────────────────────────────────────────────────────


def test_redeem_rejects_unknown_code() -> None:
    conn = _FakeConn(referrer_id=None)
    with pytest.raises(ApiError) as exc:
        asyncio.run(redeem(conn, "referee-1", "NOPE1234", reward=5))
    assert exc.value.status_code == 422


def test_redeem_rejects_own_code() -> None:
    conn = _FakeConn(referrer_id="user-123")
    with pytest.raises(ApiError) as exc:
        asyncio.run(redeem(conn, "user-123", "MYCODE12", reward=5))
    assert exc.value.status_code == 422


def test_redeem_rejects_second_use() -> None:
    conn = _FakeConn(referrer_id="referrer-1", dup=True)
    with pytest.raises(ApiError) as exc:
        asyncio.run(redeem(conn, "referee-1", "CODE1234", reward=5))
    assert exc.value.status_code == 422


def test_redeem_grants_both_sides() -> None:
    conn = _FakeConn(referrer_id="referrer-1")
    reward = asyncio.run(redeem(conn, "referee-1", "code1234", reward=5))
    assert reward == 5
    # one referral insert + two credit grants
    assert len(conn.executed) == 3
    assert sum("public.credits" in s for s in conn.executed) == 2


# ── endpoints ────────────────────────────────────────────────────────────────


def test_referrals_requires_token() -> None:
    assert client.get("/v1/referrals").status_code == 401


def test_redeem_requires_token() -> None:
    resp = client.post("/v1/referrals/redeem", json={"code": "ABCD1234"})
    assert resp.status_code == 401


def test_redeem_requires_a_code() -> None:
    resp = client.post("/v1/referrals/redeem", json={}, headers=_auth())
    assert resp.status_code == 422


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_referrals_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.services.referrals import _GRANT

    stmts = [
        "select referral_code from public.profiles where id = $1::uuid",
        "update public.profiles set referral_code = $2 "
        "where id = $1::uuid and referral_code is null returning referral_code",
        "select count(*) from public.referrals where referrer_id = $1::uuid",
        "select id from public.profiles where referral_code = $1",
        "insert into public.referrals (referee_id, referrer_id, code) "
        "values ($1::uuid, $2::uuid, $3)",
        _GRANT,
    ]

    async def run() -> None:
        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
