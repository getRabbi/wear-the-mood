"""Style Memory endpoints — what the flag gates, and what it must never gate.

The asymmetry is the design: the flag governs whether WTM **learns**, never
whether the user can **see or delete** what was learned. A kill-switch that also
switched off someone's ability to erase their own taste profile would be a
privacy failure dressed as a rollout control (§10, §12.2).
"""

from __future__ import annotations

import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.tests.test_giveaway_chat import _Conn, _Pool

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_ID = "11111111-1111-4111-8111-111111111111"

client = TestClient(app)


@pytest.fixture(autouse=True)
def _use_test_secret(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _auth() -> dict:
    now = int(time.time())
    token = jwt.encode(
        {
            "sub": USER_ID,
            "aud": "authenticated",
            "email": "a@b.com",
            "role": "authenticated",
            "iat": now,
            "exp": now + 3600,
        },
        TEST_SECRET,
        algorithm="HS256",
    )
    return {"Authorization": f"Bearer {token}"}


def _install(monkeypatch: pytest.MonkeyPatch, conn: _Conn):
    import app.routers.v1.style_memory as sm_mod

    monkeypatch.setattr(sm_mod, "get_pool", lambda: _Pool(conn))
    return sm_mod


def _conn(*, enabled: bool = True, profile: dict | None = None) -> _Conn:
    return _Conn(
        [
            ("fetchval", "from public.feature_flags", enabled),
            ("fetchrow", "from public.style_memory_profiles", profile),
            ("fetchval", "delete from public.style_memory_signals", 7),
            ("fetchval", "insert into public.style_memory_signals", "signal-id"),
            ("fetch", "from public.style_memory_signals", []),
        ]
    )


# ── reading is never gated ───────────────────────────────────────────────────


def test_the_profile_is_readable_with_the_flag_off(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn(enabled=False))
    resp = client.get("/v1/style-memory", headers=_auth())
    assert resp.status_code == 200
    # No row yet is "we have learned nothing", not a 404.
    assert resp.json()["signal_count"] == 0
    assert resp.json()["preference_summary"] is None


def test_an_absent_profile_is_an_empty_shape_not_an_error(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, _conn(profile=None))
    body = client.get("/v1/style-memory", headers=_auth()).json()
    assert body["preferred_colors"] == []
    assert body["personalization_enabled"] is True


# ── deleting is never gated ──────────────────────────────────────────────────


def test_reset_works_with_the_flag_off(monkeypatch: pytest.MonkeyPatch) -> None:
    """A deletion right does not depend on a rollout flag."""
    _install(monkeypatch, _conn(enabled=False))
    resp = client.post("/v1/style-memory/reset", headers=_auth())
    assert resp.status_code == 200
    assert resp.json()["deleted_signals"] == 7


def test_turning_personalization_off_works_with_the_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Asking us to stop using their taste must not require the feature to be
    on — and must not delete anything either."""
    profile = {
        "user_id": USER_ID,
        "version": 1,
        "confidence": 0,
        "signal_count": 3,
        "personalization_enabled": False,
        "preference_summary": None,
        "preferred_colors": "[]",
        "avoided_colors": "[]",
        "preferred_silhouettes": "[]",
        "avoided_silhouettes": "[]",
        "preferred_aesthetics": "[]",
        "preferred_occasions": "[]",
        "preferred_moods": "[]",
        "fit_visual_preferences": "[]",
    }
    _install(monkeypatch, _conn(enabled=False, profile=profile))
    resp = client.post("/v1/style-memory/personalization", json={"enabled": False}, headers=_auth())
    assert resp.status_code == 200
    body = resp.json()
    assert body["personalization_enabled"] is False
    # Kept, not erased.
    assert body["signal_count"] == 3


# ── writing IS gated ─────────────────────────────────────────────────────────


def test_recording_a_signal_is_404_with_the_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, _conn(enabled=False))
    resp = client.post(
        "/v1/style-memory/signals", json={"signal_type": "keep_look"}, headers=_auth()
    )
    assert resp.status_code == 404


def test_correcting_a_preference_is_404_with_the_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, _conn(enabled=False))
    resp = client.patch(
        "/v1/style-memory",
        json={"facet": "preferred_colors", "value": "olive"},
        headers=_auth(),
    )
    assert resp.status_code == 404


def test_no_signal_is_written_when_the_flag_is_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _conn(enabled=False)
    _install(monkeypatch, conn)
    client.post("/v1/style-memory/signals", json={"signal_type": "keep_look"}, headers=_auth())
    assert not any("insert into public.style_memory_signals" in sql for _m, sql, _a in conn.calls)


# ── input validation ─────────────────────────────────────────────────────────


def test_an_unknown_signal_type_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.post(
        "/v1/style-memory/signals", json={"signal_type": "buy_the_shop"}, headers=_auth()
    )
    assert resp.status_code == 422


def test_an_unknown_facet_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.patch(
        "/v1/style-memory",
        json={"facet": "favourite_pizza", "value": "margherita"},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_an_unknown_rejection_reason_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.post(
        "/v1/style-memory/signals",
        json={"signal_type": "reject_look", "reason": "vibes"},
        headers=_auth(),
    )
    assert resp.status_code == 422


# ── auth ─────────────────────────────────────────────────────────────────────


def test_every_style_memory_route_requires_a_token() -> None:
    assert client.get("/v1/style-memory").status_code == 401
    assert client.post("/v1/style-memory/signals", json={}).status_code == 401
    assert client.post("/v1/style-memory/reset").status_code == 401
    assert client.get("/v1/style-memory/signals").status_code == 401
