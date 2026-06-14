import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.tryon_photo import TryonPhotoCreate

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
    payload = {
        "sub": "user-123",
        "aud": "authenticated",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    return {"Authorization": f"Bearer {jwt.encode(payload, TEST_SECRET, algorithm='HS256')}"}


def test_list_requires_token() -> None:
    assert client.get("/v1/tryon-photos").status_code == 401


def test_post_requires_token() -> None:
    resp = client.post("/v1/tryon-photos", json={"storage_path": "u/tryon/x.jpg"})
    assert resp.status_code == 401


def test_post_rejects_out_of_range_score() -> None:
    resp = client.post(
        "/v1/tryon-photos",
        json={"storage_path": "u/tryon/x.jpg", "quality_score": 150},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_model_score_bounds() -> None:
    assert TryonPhotoCreate(storage_path="a", quality_score=88).quality_score == 88
    with pytest.raises(ValueError):
        TryonPhotoCreate(storage_path="a", quality_score=200)


def test_get_authed_reaches_db_layer() -> None:
    no_raise = TestClient(app, raise_server_exceptions=False)
    resp = no_raise.get("/v1/tryon-photos", headers=_auth())
    assert resp.status_code not in (401, 422)
