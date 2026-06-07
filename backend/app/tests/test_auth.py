import time

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


def _token(
    secret: str = TEST_SECRET,
    sub: str = "user-123",
    aud: str = "authenticated",
    email: str = "a@b.com",
    exp_delta: int = 3600,
) -> str:
    now = int(time.time())
    payload = {
        "sub": sub,
        "aud": aud,
        "email": email,
        "role": "authenticated",
        "iat": now,
        "exp": now + exp_delta,
    }
    return jwt.encode(payload, secret, algorithm="HS256")


def test_me_requires_token() -> None:
    resp = client.get("/v1/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_me_with_valid_token() -> None:
    resp = client.get("/v1/me", headers={"Authorization": f"Bearer {_token()}"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == "user-123"
    assert body["email"] == "a@b.com"


def test_me_rejects_bad_signature() -> None:
    bad = _token(secret="a-totally-different-wrong-secret-0123456789")
    resp = client.get("/v1/me", headers={"Authorization": f"Bearer {bad}"})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_me_rejects_expired() -> None:
    expired = _token(exp_delta=-10)
    resp = client.get("/v1/me", headers={"Authorization": f"Bearer {expired}"})
    assert resp.status_code == 401


def test_me_rejects_wrong_audience() -> None:
    wrong = _token(aud="not-authenticated")
    resp = client.get("/v1/me", headers={"Authorization": f"Bearer {wrong}"})
    assert resp.status_code == 401
