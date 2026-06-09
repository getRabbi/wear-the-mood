import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.credits import CreditsState
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
