"""Health/readiness + maintenance-mode + emergency guard (blueprint §4.6, §11.9)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

client = TestClient(app)


@pytest.fixture
def _restore_settings():
    yield
    get_settings.cache_clear()


def test_healthz_is_liveness_only() -> None:
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_readyz_reports_build_metadata() -> None:
    r = client.get("/readyz")
    assert r.status_code in (200, 503)  # 503 without a DB pool in unit tests
    body = r.json()
    assert set(body) >= {"status", "db", "environment", "version", "commit"}


def test_legacy_v1_health_preserved() -> None:
    r = client.get("/v1/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_maintenance_blocks_mutations_but_not_reads_or_health(
    monkeypatch, _restore_settings
) -> None:
    monkeypatch.setenv("MAINTENANCE_MODE", "true")
    get_settings.cache_clear()

    blocked = client.post("/")
    assert blocked.status_code == 503
    assert blocked.json()["error"]["code"] == "MAINTENANCE"
    assert blocked.headers.get("Retry-After") == "30"

    assert client.get("/healthz").status_code == 200  # health never gated
    assert client.get("/").status_code == 200  # safe reads still served


def test_emergency_guard_blocks_everything_except_health(monkeypatch, _restore_settings) -> None:
    monkeypatch.setenv("EMERGENCY_API", "true")
    monkeypatch.setenv("EMERGENCY_API_ENABLED", "false")
    get_settings.cache_clear()

    assert client.get("/").status_code == 503  # break-glass app is disabled
    assert client.get("/healthz").status_code == 200  # liveness always answers
