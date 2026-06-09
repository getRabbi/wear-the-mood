import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import CreditsState, _plan_spend, has_credit
from app.main import app

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _token(sub: str = "user-123") -> str:
    now = int(time.time())
    payload = {
        "sub": sub,
        "aud": "authenticated",
        "email": "a@b.com",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def test_credits_requires_token() -> None:
    # Auth is checked before the handler touches the DB, so this holds with no DSN.
    resp = client.get("/v1/credits")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_credits_rejects_bad_signature() -> None:
    bad = jwt.encode(
        {"sub": "user-123", "aud": "authenticated", "exp": int(time.time()) + 3600},
        "a-totally-different-wrong-secret-0123456789",
        algorithm="HS256",
    )
    resp = client.get("/v1/credits", headers={"Authorization": f"Bearer {bad}"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_daily_free_remaining_normal() -> None:
    state = CreditsState(balance=10, daily_free_used=2, daily_free_limit=5)
    assert state.daily_free_remaining == 3


def test_daily_free_remaining_clamps_to_zero() -> None:
    # Limit lowered below what's already been used must not go negative.
    state = CreditsState(balance=0, daily_free_used=7, daily_free_limit=5)
    assert state.daily_free_remaining == 0


def test_has_credit() -> None:
    assert has_credit(CreditsState(balance=0, daily_free_used=4, daily_free_limit=5)) is True
    assert has_credit(CreditsState(balance=2, daily_free_used=5, daily_free_limit=5)) is True
    assert has_credit(CreditsState(balance=0, daily_free_used=5, daily_free_limit=5)) is False


def test_plan_spend_uses_free_bucket_first() -> None:
    # Free available: charge the bucket, leave paid balance untouched.
    assert _plan_spend(balance=10, free_used=0, free_limit=5, cost=1) == (10, 1, "free")


def test_plan_spend_falls_back_to_paid_when_free_exhausted() -> None:
    assert _plan_spend(balance=3, free_used=5, free_limit=5, cost=1) == (2, 5, "paid")


def test_plan_spend_insufficient_returns_none() -> None:
    assert _plan_spend(balance=0, free_used=5, free_limit=5, cost=1) is None


def test_plan_spend_cost_larger_than_free_remaining_uses_paid() -> None:
    # 1 free left but cost 2 -> can't split, so it comes from paid balance.
    assert _plan_spend(balance=4, free_used=4, free_limit=5, cost=2) == (2, 4, "paid")
