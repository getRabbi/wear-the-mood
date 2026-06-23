import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import CreditsState, _draw, has_credit
from app.core.plans import HD_COST, STD_COST
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


def test_free_trial_is_three_total_one_time(monkeypatch: pytest.MonkeyPatch) -> None:
    # Canonical rule (Issue 3/4): 3 free AI try-ons TOTAL, then the paywall.
    monkeypatch.delenv("FREE_TRYON_TRIAL_CREDITS", raising=False)
    get_settings.cache_clear()
    assert get_settings().free_tryon_trial_credits == 3
    # First three are free; the fourth has nothing left (no daily reset).
    assert has_credit(CreditsState(balance=0, daily_free_used=2, daily_free_limit=3)) is True
    assert has_credit(CreditsState(balance=0, daily_free_used=3, daily_free_limit=3)) is False


# ── _draw: free trial → plan balance → top-up, drawing across buckets ────────


def test_draw_free_first() -> None:
    # Free available: take from the trial, leave plan balance + top-up untouched.
    assert _draw(free_remaining=5, balance=10, topup=3, cost=1) == (1, 0, 0)


def test_draw_falls_through_to_plan_then_topup() -> None:
    assert _draw(free_remaining=0, balance=3, topup=9, cost=1) == (0, 1, 0)
    assert _draw(free_remaining=0, balance=0, topup=9, cost=2) == (0, 0, 2)


def test_draw_splits_across_buckets() -> None:
    # 1 free + 1 plan + 2 top-up covers a cost-4 HD render.
    assert _draw(free_remaining=1, balance=1, topup=5, cost=4) == (1, 1, 2)
    # 2 plan + 2 top-up.
    assert _draw(free_remaining=0, balance=2, topup=3, cost=4) == (0, 2, 2)


def test_draw_insufficient_returns_none() -> None:
    assert _draw(free_remaining=0, balance=1, topup=1, cost=4) is None
    assert _draw(free_remaining=0, balance=0, topup=0, cost=1) is None


def test_has_credit_is_cost_aware() -> None:
    s = CreditsState(balance=1, daily_free_used=5, daily_free_limit=5, topup_balance=2)
    assert s.total_available == 3
    assert has_credit(s, STD_COST) is True  # 3 >= 1
    assert has_credit(s, 3) is True
    assert has_credit(s, HD_COST) is False  # 3 < 4
    # HD needs 4: a Pro Max with full plan balance can afford it.
    assert has_credit(CreditsState(balance=150, daily_free_used=0, daily_free_limit=3), HD_COST)
