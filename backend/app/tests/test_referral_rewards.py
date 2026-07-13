"""Referral REWARDS program (install attribution, §24) — eligibility, fraud,
idempotency, redirect + token hygiene. Logic is exercised through stateful fake
connections (no live DB needed); a live-SQL test validates the new statements
against a real database when CONNECTION_STRING is set."""

from __future__ import annotations

import asyncio
import time
from datetime import UTC, datetime, timedelta

import asyncpg
import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.referrals import (
    ClaimStatus,
    _install_hash,
    _sha256,
    build_referral_url,
    claim,
    create_attribution,
    resolve_redirect,
)

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
client = TestClient(app)


@pytest.fixture(autouse=True)
def _secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth(sub: str = "referred-1") -> dict:
    now = int(time.time())
    token = jwt.encode(
        {"sub": sub, "aud": "authenticated", "role": "authenticated",
         "iat": now, "exp": now + 3600},
        TEST_SECRET, algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


class _FakeTx:
    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _AttrConn:
    """Fake conn for create_attribution / resolve_redirect."""

    def __init__(self, referrer_id: str | None = "referrer-1") -> None:
        self.referrer_id = referrer_id
        self.inserts: list[tuple] = []

    def transaction(self):
        return _FakeTx()

    async def fetchval(self, sql: str, *args):
        if "where referral_code = $1" in sql:
            return self.referrer_id
        return None

    async def execute(self, sql: str, *args):
        self.inserts.append((sql, args))
        return "INSERT 0 1"


class _ClaimConn:
    """Stateful fake conn modelling the claim path's queries."""

    def __init__(
        self,
        *,
        attribution: dict | None,
        existing_claim_reward: int | None = None,
        referrer_exists: bool = True,
        referred_created_at: datetime | None = None,
        used_install_hashes: set[str] | None = None,
    ) -> None:
        self.attribution = attribution  # dict keyed like the DB row, or None
        self.existing_claim_reward = existing_claim_reward
        self.referrer_exists = referrer_exists
        self.referred_created_at = referred_created_at
        self.used_install_hashes = used_install_hashes or set()
        self.grants: list[tuple] = []
        self.consumed = False
        self.inserted_claim: tuple | None = None
        self.notifications: list[tuple] = []

    def transaction(self):
        return _FakeTx()

    async def fetchval(self, sql: str, *args):
        if "from public.referral_claims where referred_user_id" in sql:
            return self.existing_claim_reward
        if "from public.profiles where id" in sql:
            return 1 if self.referrer_exists else None
        if "from auth.users where id" in sql:
            return self.referred_created_at
        if "from public.referral_claims where install_hash" in sql:
            return 1 if args[0] in self.used_install_hashes else None
        if "app_grant_credits" in sql:
            self.grants.append(args)  # (user, amount, reason, ref, set_plan, target)
            return True
        return None

    async def fetchrow(self, sql: str, *args):
        if "from public.referral_attributions where token_hash" in sql:
            return self.attribution
        return None

    async def execute(self, sql: str, *args):
        if "update public.referral_attributions" in sql:
            self.consumed = True
        elif "insert into public.referral_claims" in sql:
            self.inserted_claim = args
        elif "insert into public.notifications" in sql:
            self.notifications.append(args)
        return "INSERT 0 1"


def _attr(*, referrer="referrer-1", consumed=False, expired=False, clicked_minutes_ago=1):
    now = datetime.now(UTC)
    return {
        "id": "attr-1",
        "referrer_id": referrer,
        "expires_at": now - timedelta(minutes=5) if expired else now + timedelta(days=29),
        "consumed_at": now if consumed else None,
        "created_at": now - timedelta(minutes=clicked_minutes_ago),
    }


def _run(coro):
    return asyncio.run(coro)


# ── code / token hygiene ─────────────────────────────────────────────────────


def test_referral_url_uses_stable_code_not_uuid() -> None:
    url = build_referral_url("AB2CD3EF")
    assert url == "https://wearthemood.com/r/AB2CD3EF"
    assert "@" not in url and "-" not in url.rsplit("/", 1)[-1]  # no email / uuid


def test_sha256_and_install_hash() -> None:
    assert _sha256("abc") == _sha256("abc")
    assert _sha256("abc") != _sha256("abd")
    assert _install_hash(None) is None
    assert _install_hash("  ") is None
    h = _install_hash("device-uuid-1")
    assert h and h != "device-uuid-1"  # hashed, not raw


def test_create_attribution_stores_hash_not_raw_and_expires() -> None:
    conn = _AttrConn(referrer_id="referrer-1")
    raw, expires = _run(create_attribution(conn, "MYCODE12"))
    assert raw and len(raw) >= 20
    # The raw token is NEVER stored — only its sha256 hash.
    insert_sql, insert_args = conn.inserts[0]
    assert "referral_attributions" in insert_sql
    assert raw not in insert_args
    assert _sha256(raw) in insert_args
    # ~30-day expiry.
    assert timedelta(days=29) < (expires - datetime.now(UTC)) < timedelta(days=31)


def test_create_attribution_unknown_code_returns_none() -> None:
    conn = _AttrConn(referrer_id=None)
    assert _run(create_attribution(conn, "NOPE0000")) is None


# ── redirect ─────────────────────────────────────────────────────────────────


def test_resolve_redirect_valid_code_goes_to_play_with_token_only() -> None:
    conn = _AttrConn(referrer_id="referrer-1")
    url = _run(resolve_redirect(conn, "MYCODE12"))
    assert url.startswith("https://play.google.com/store/apps/details?id=com.fashionos.app")
    assert "referral_token%3D" in url  # url-encoded referrer payload
    assert "utm_source%3Dreferral" in url
    # No private identifiers leak into the Play URL.
    assert "referrer-1" not in url and "@" not in url


def test_resolve_redirect_invalid_code_lands_safely() -> None:
    conn = _AttrConn(referrer_id=None)
    url = _run(resolve_redirect(conn, "GARBAGE!"))
    assert url == "https://wearthemood.com"  # landing, not an exception/open redirect


# ── eligibility matrix ───────────────────────────────────────────────────────


def _claim(conn, *, token="rawtoken", referred="referred-1", install="dev-1"):
    return _run(claim(conn, referred_user_id=referred, token=token, install_id=install))


def test_new_eligible_referral_awards_ten_to_referrer_only() -> None:
    conn = _ClaimConn(
        attribution=_attr(referrer="referrer-1"),
        referred_created_at=datetime.now(UTC),  # just signed up (after click)
    )
    result = _claim(conn, referred="referred-1")
    assert result.status == ClaimStatus.awarded
    assert result.reward_credits == 10
    assert conn.consumed is True
    assert conn.inserted_claim is not None
    # Exactly one grant, to the REFERRER, 10 credits, referral_bonus, top-up bucket.
    assert len(conn.grants) == 1
    user, amount, reason, ref, _set_plan, target = conn.grants[0]
    assert user == "referrer-1"
    assert amount == 10
    assert reason == "referral_bonus"
    assert ref.startswith("referral:")
    assert target == "topup"
    # The referred user is NOT granted anything.
    assert all(g[0] != "referred-1" for g in conn.grants)
    assert len(conn.notifications) == 1  # referrer notified


def test_self_referral_is_rejected() -> None:
    conn = _ClaimConn(
        attribution=_attr(referrer="referred-1"),
        referred_created_at=datetime.now(UTC),
    )
    result = _claim(conn, referred="referred-1")
    assert result.status == ClaimStatus.self_referral
    assert conn.grants == []
    assert conn.consumed is False


def test_existing_user_is_rejected() -> None:
    conn = _ClaimConn(
        attribution=_attr(clicked_minutes_ago=1),
        referred_created_at=datetime.now(UTC) - timedelta(days=365),  # old account
    )
    result = _claim(conn)
    assert result.status == ClaimStatus.not_eligible_existing_user
    assert conn.grants == []


def test_expired_token_is_rejected() -> None:
    conn = _ClaimConn(
        attribution=_attr(expired=True),
        referred_created_at=datetime.now(UTC),
    )
    result = _claim(conn)
    assert result.status == ClaimStatus.expired
    assert conn.grants == []


def test_reused_token_is_rejected() -> None:
    conn = _ClaimConn(
        attribution=_attr(consumed=True),
        referred_created_at=datetime.now(UTC),
    )
    result = _claim(conn)
    assert result.status == ClaimStatus.reused
    assert conn.grants == []


def test_invalid_token_is_rejected() -> None:
    conn = _ClaimConn(attribution=None)
    result = _claim(conn)
    assert result.status == ClaimStatus.invalid
    assert conn.grants == []


def test_empty_token_is_invalid() -> None:
    conn = _ClaimConn(attribution=None)
    result = _run(claim(conn, referred_user_id="u", token="", install_id="d"))
    assert result.status == ClaimStatus.invalid


def test_already_claimed_is_idempotent_no_regrant() -> None:
    conn = _ClaimConn(
        attribution=_attr(),
        existing_claim_reward=10,  # this user already has an award
        referred_created_at=datetime.now(UTC),
    )
    result = _claim(conn)
    assert result.status == ClaimStatus.already_claimed
    assert result.reward_credits == 10
    assert conn.grants == []  # no second grant
    assert conn.consumed is False


def test_reused_installation_is_rejected() -> None:
    conn = _ClaimConn(
        attribution=_attr(),
        referred_created_at=datetime.now(UTC),
        used_install_hashes={_install_hash("dev-1")},
    )
    result = _claim(conn, install="dev-1")
    assert result.status == ClaimStatus.reused
    assert conn.grants == []


def test_program_disabled_awards_nothing() -> None:
    import os

    os.environ["REFERRAL_ENABLED"] = "false"
    get_settings.cache_clear()
    try:
        conn = _ClaimConn(attribution=_attr(), referred_created_at=datetime.now(UTC))
        result = _claim(conn)
        assert result.status == ClaimStatus.disabled
        assert conn.grants == []
    finally:
        del os.environ["REFERRAL_ENABLED"]
        get_settings.cache_clear()


def test_bonus_amount_comes_from_server_config_not_client() -> None:
    import os

    os.environ["REFERRAL_REFERRER_BONUS_CREDITS"] = "25"
    get_settings.cache_clear()
    try:
        conn = _ClaimConn(attribution=_attr(), referred_created_at=datetime.now(UTC))
        result = _claim(conn)
        assert result.reward_credits == 25  # server config, not any client value
        assert conn.grants[0][1] == 25
    finally:
        del os.environ["REFERRAL_REFERRER_BONUS_CREDITS"]
        get_settings.cache_clear()


# ── endpoints: auth + client cannot supply identity/amount ───────────────────


def test_me_requires_auth() -> None:
    assert client.get("/v1/referrals/me").status_code == 401


def test_claim_requires_auth() -> None:
    assert client.post("/v1/referrals/claim", json={"token": "x"}).status_code == 401


def test_click_validates_and_is_public() -> None:
    # Unknown code → 422 (public endpoint, no auth needed to mint on a valid code,
    # but an unknown one is rejected without a token). Live DB not required — the
    # code lookup fails closed against an empty/absent pool only when DB is up; in
    # unit context this asserts the route + schema wiring is present (non-401).
    resp = client.post("/v1/referrals/click", json={})
    assert resp.status_code == 422  # missing required `code`


def test_claim_ignores_client_supplied_user_ids() -> None:
    # The request model has no referrer/referred/amount fields; pydantic drops
    # extras, so a spoofed body can't set identity or reward.
    from app.models.referral import ReferralClaimRequest

    parsed = ReferralClaimRequest.model_validate(
        {"token": "t", "referred_user_id": "attacker", "reward": 9999, "amount": 9999}
    )
    assert not hasattr(parsed, "reward")
    assert not hasattr(parsed, "referred_user_id")
    assert parsed.token == "t"


# ── live SQL validation (skips without a DSN) ────────────────────────────────


def test_referral_rewards_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    stmts = [
        "select public.app_rate_limit($1, $2, $3)",
        "insert into public.referral_attributions "
        "(token_hash, referrer_id, referral_code, platform, expires_at) "
        "values ($1, $2::uuid, $3, $4, $5)",
        "select id, referrer_id, expires_at, consumed_at, created_at "
        "from public.referral_attributions where token_hash = $1 for update",
        "select reward_credits from public.referral_claims "
        "where referred_user_id = $1::uuid",
        "select created_at from auth.users where id = $1::uuid",
        "insert into public.referral_claims "
        "(id, referrer_id, referred_user_id, attribution_id, install_hash, "
        " platform, reward_credits, credit_ref, credited_at) "
        "values ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, now())",
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
