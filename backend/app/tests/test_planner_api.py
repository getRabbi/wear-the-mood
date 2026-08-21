"""Planner endpoints — the flag gate, the cost guarantee, and PATCH validation.

The guarantee worth protecting: **a mood plan is free.** No endpoint in
`routers/v1/planner.py` may reserve a credit, touch `credit_transactions`, or
reach a provider. If that ever stops being true the planner stops being a reason
to open the app on a day the user has nothing to spend (RETENTION spec §14).
"""

from __future__ import annotations

import time
import uuid

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
    import app.routers.v1.planner as planner_mod

    monkeypatch.setattr(planner_mod, "get_pool", lambda: _Pool(conn))
    return planner_mod


def _event_row(**over) -> dict:
    from datetime import UTC, datetime

    row = {
        "id": uuid.uuid4(),
        "name": "Nadia wedding",
        "event_at": datetime(2026, 9, 5, 12, tzinfo=UTC),
        "occasion": "wedding",
        "look_ref": None,
        "look_image_url": None,
        "note": None,
        "reminder_opt_in": False,
        "created_at": datetime(2026, 8, 20, tzinfo=UTC),
    }
    row.update(over)
    return row


def _conn(*, planner_on: bool = True, rows: list | None = None, row: dict | None = None) -> _Conn:
    return _Conn(
        [
            ("fetchval", "from public.feature_flags", planner_on),
            ("fetch", "from public.wardrobe_items", rows or []),
            ("fetch", "from public.style_events", rows or []),
            ("fetchrow", "from public.style_memory_profiles", None),
            ("fetchrow", "insert into public.mood_plans", row),
            ("fetchrow", "insert into public.style_events", row),
            ("fetchrow", "update public.style_events", row),
        ]
    )


# ── the flag gate ────────────────────────────────────────────────────────────


def test_a_mood_plan_is_404_while_the_flag_is_off(monkeypatch: pytest.MonkeyPatch) -> None:
    """Server-side, not merely a hidden button: an old or hand-rolled client
    cannot write into a feature that is switched off."""
    _install(monkeypatch, _conn(planner_on=False))
    resp = client.post("/v1/plans/mood", json={"mood": "calm"}, headers=_auth())
    assert resp.status_code == 404


def test_creating_an_event_is_404_while_the_flag_is_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _install(monkeypatch, _conn(planner_on=False))
    resp = client.post(
        "/v1/events",
        json={"name": "Dinner", "event_at": "2026-09-05T12:00:00Z"},
        headers=_auth(),
    )
    assert resp.status_code == 404


def test_listing_events_works_even_with_the_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A kill-switch must not hide data the user already saved (§51)."""
    _install(monkeypatch, _conn(planner_on=False, rows=[]))
    resp = client.get("/v1/events", headers=_auth())
    assert resp.status_code == 200
    assert resp.json()["events"] == []


def test_deleting_an_event_works_even_with_the_flag_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Deleting your own data must never depend on a rollout flag (§10)."""
    event_id = uuid.uuid4()
    conn = _Conn(
        [
            ("fetchval", "from public.feature_flags", False),
            ("fetchval", "delete from public.style_events", event_id),
        ]
    )
    _install(monkeypatch, conn)
    resp = client.delete(f"/v1/events/{event_id}", headers=_auth())
    assert resp.status_code == 204


# ── the cost guarantee ───────────────────────────────────────────────────────


def test_a_mood_plan_never_touches_credits(monkeypatch: pytest.MonkeyPatch) -> None:
    from datetime import UTC, datetime

    conn = _conn(row={"id": uuid.uuid4(), "created_at": datetime(2026, 8, 20, tzinfo=UTC)})
    _install(monkeypatch, conn)
    resp = client.post("/v1/plans/mood", json={"mood": "calm", "occasion": "work"}, headers=_auth())
    assert resp.status_code == 200
    touched = [
        sql for _m, sql, _a in conn.calls if "credit" in sql.lower() or "tryon_jobs" in sql.lower()
    ]
    assert touched == [], f"a free plan touched a paid system: {touched}"


def test_the_plan_carries_direction_not_an_image(monkeypatch: pytest.MonkeyPatch) -> None:
    from datetime import UTC, datetime

    conn = _conn(row={"id": uuid.uuid4(), "created_at": datetime(2026, 8, 20, tzinfo=UTC)})
    _install(monkeypatch, conn)
    body = client.post("/v1/plans/mood", json={"mood": "bold"}, headers=_auth()).json()
    assert body["headline"]
    assert body["lines"]
    # An empty closet cannot name real pieces, and says so rather than pretending.
    assert body["generic"] is True
    assert "image_url" not in body


def test_an_unknown_mood_is_a_typed_422(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.post("/v1/plans/mood", json={"mood": "hangry"}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


# ── PATCH validation ─────────────────────────────────────────────────────────


def test_an_explicit_null_on_a_required_field_is_a_422_not_a_500(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`{"name": null}` means "clear it", which the column cannot express. It
    has to come back as a typed validation error, not a NotNullViolation
    surfacing as an unhandled 500 (§13)."""
    _install(monkeypatch, _conn())
    resp = client.patch(f"/v1/events/{uuid.uuid4()}", json={"name": None}, headers=_auth())
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_a_whitespace_only_name_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.patch(f"/v1/events/{uuid.uuid4()}", json={"name": "   "}, headers=_auth())
    assert resp.status_code == 422


def test_an_empty_patch_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn())
    resp = client.patch(f"/v1/events/{uuid.uuid4()}", json={}, headers=_auth())
    assert resp.status_code == 422


def test_patching_somebody_elses_event_is_a_404(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ownership lives in the UPDATE, so a miss never leaks that the row exists."""
    conn = _Conn(
        [
            ("fetchval", "from public.feature_flags", True),
            ("fetchrow", "update public.style_events", None),
        ]
    )
    _install(monkeypatch, conn)
    resp = client.patch(f"/v1/events/{uuid.uuid4()}", json={"note": "hi"}, headers=_auth())
    assert resp.status_code == 404


def test_a_partial_patch_updates_only_what_it_names(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    conn = _conn(row=_event_row(note="black satin"))
    _install(monkeypatch, conn)
    resp = client.patch(f"/v1/events/{uuid.uuid4()}", json={"note": "black satin"}, headers=_auth())
    assert resp.status_code == 200
    update = next(sql for _m, sql, _a in conn.calls if "update public.style_events" in sql)
    assert "note = $3" in update
    assert "name =" not in update
    assert "event_at =" not in update


# ── auth ─────────────────────────────────────────────────────────────────────


def test_every_planner_route_requires_a_token() -> None:
    assert client.post("/v1/plans/mood", json={"mood": "calm"}).status_code == 401
    assert client.get("/v1/plans/mood/latest").status_code == 401
    assert client.get("/v1/events").status_code == 401
    assert client.post("/v1/events", json={}).status_code == 401
