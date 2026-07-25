"""Weather API — auth gate + current/geocode over the stub provider (no network)."""

from __future__ import annotations

import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.weather import get_weather_provider

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _stub_weather(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    monkeypatch.setenv("WEATHER_PROVIDER", "stub")
    get_settings.cache_clear()
    get_weather_provider.cache_clear()
    yield
    get_settings.cache_clear()
    get_weather_provider.cache_clear()


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


def test_current_requires_auth() -> None:
    assert client.get("/v1/weather/current?latitude=23.8&longitude=90.4").status_code == 401


def test_current_returns_snapshot() -> None:
    resp = client.get("/v1/weather/current?latitude=23.8&longitude=90.4", headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert body["condition"] == "Partly cloudy"
    assert body["temp_c"] == 24.0


def test_current_validates_coordinates() -> None:
    # Latitude out of range → 422 validation, never a provider call.
    resp = client.get("/v1/weather/current?latitude=200&longitude=0", headers=_auth())
    assert resp.status_code == 422


def test_geocode_requires_auth() -> None:
    assert client.get("/v1/weather/geocode?q=Dhaka").status_code == 401


def test_geocode_returns_places() -> None:
    resp = client.get("/v1/weather/geocode?q=Dhaka", headers=_auth())
    assert resp.status_code == 200
    places = resp.json()
    assert places and places[0]["latitude"] == 23.78
