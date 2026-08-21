"""POST /v1/tryon/results/{id}/feedback — Keep it / Not me (spec §18, §19.3).

The guarantee this file exists to protect:

    **Disliking a render is not a refund.**

A render that failed technically, lost a garment, or was rejected by the
fidelity gate was already refunded by the worker before the user ever saw a
result. What reaches this endpoint is a render that WORKED. Refunding taste
would turn "show me another" into an unlimited free-render loop, and would also
be untrue about what went wrong — because nothing did.
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
    import app.routers.v1.tryon as tryon_mod

    monkeypatch.setattr(tryon_mod, "get_pool", lambda: _Pool(conn))
    return tryon_mod


def _result_row(result_id: str) -> dict:
    return {"id": result_id, "job_id": str(uuid.uuid4())}


def _conn(result_id: str, *, style_memory_on: bool = False) -> _Conn:
    return _Conn(
        [
            ("fetchrow", "update public.tryon_results", _result_row(result_id)),
            ("fetchval", "from public.feature_flags", style_memory_on),
        ]
    )


# ── auth and validation ──────────────────────────────────────────────────────


def test_feedback_requires_a_token() -> None:
    resp = client.post(f"/v1/tryon/results/{uuid.uuid4()}/feedback", json={"outcome": "kept"})
    assert resp.status_code == 401


def test_an_unknown_outcome_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn(str(uuid.uuid4())))
    resp = client.post(
        f"/v1/tryon/results/{uuid.uuid4()}/feedback",
        json={"outcome": "meh"},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_a_rejection_must_say_why(monkeypatch: pytest.MonkeyPatch) -> None:
    """ "Not me" with no reason teaches nothing, so we ask for one."""
    _install(monkeypatch, _conn(str(uuid.uuid4())))
    resp = client.post(
        f"/v1/tryon/results/{uuid.uuid4()}/feedback",
        json={"outcome": "rejected"},
        headers=_auth(),
    )
    assert resp.status_code == 422
    assert resp.json()["error"]["code"] == "VALIDATION_ERROR"


def test_an_unknown_reason_is_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    _install(monkeypatch, _conn(str(uuid.uuid4())))
    resp = client.post(
        f"/v1/tryon/results/{uuid.uuid4()}/feedback",
        json={"outcome": "rejected", "reason": "vibes"},
        headers=_auth(),
    )
    assert resp.status_code == 422


def test_somebody_elses_result_is_a_404(monkeypatch: pytest.MonkeyPatch) -> None:
    """Ownership lives in the UPDATE, so a miss is indistinguishable from
    "no such row" — it never leaks that the result exists."""
    conn = _Conn([("fetchrow", "update public.tryon_results", None)])
    _install(monkeypatch, conn)
    resp = client.post(
        f"/v1/tryon/results/{uuid.uuid4()}/feedback",
        json={"outcome": "kept"},
        headers=_auth(),
    )
    assert resp.status_code == 404


# ── the money guarantee ──────────────────────────────────────────────────────


def _credit_statements(conn: _Conn) -> list[str]:
    return [
        sql
        for _method, sql, _args in conn.calls
        if "credits" in sql.lower() or "credit_transactions" in sql.lower()
    ]


def test_keeping_a_look_never_touches_credits(monkeypatch: pytest.MonkeyPatch) -> None:
    result_id = str(uuid.uuid4())
    conn = _conn(result_id)
    _install(monkeypatch, conn)
    resp = client.post(
        f"/v1/tryon/results/{result_id}/feedback",
        json={"outcome": "kept"},
        headers=_auth(),
    )
    assert resp.status_code == 200
    assert resp.json()["outcome"] == "kept"
    assert _credit_statements(conn) == []


def test_rejecting_a_look_never_refunds(monkeypatch: pytest.MonkeyPatch) -> None:
    """The whole point (§19.3): subjective dislike is a taste signal, not money."""
    result_id = str(uuid.uuid4())
    conn = _conn(result_id)
    _install(monkeypatch, conn)
    resp = client.post(
        f"/v1/tryon/results/{result_id}/feedback",
        json={"outcome": "rejected", "reason": "not_my_style"},
        headers=_auth(),
    )
    assert resp.status_code == 200
    assert resp.json()["outcome"] == "rejected"
    assert _credit_statements(conn) == []


# ── the flag ─────────────────────────────────────────────────────────────────


def test_the_verdict_is_stored_even_with_style_memory_off(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The outcome is a fact about the render and feeds the cost ledger. Only
    the LEARNING is gated."""
    result_id = str(uuid.uuid4())
    conn = _conn(result_id, style_memory_on=False)
    _install(monkeypatch, conn)
    resp = client.post(
        f"/v1/tryon/results/{result_id}/feedback",
        json={"outcome": "kept"},
        headers=_auth(),
    )
    body = resp.json()
    assert resp.status_code == 200
    assert body["outcome"] == "kept"
    assert body["recorded"] is False
    assert body["profile"] is None
    assert any("update public.tryon_results" in sql for _m, sql, _a in conn.calls)


def test_no_signal_is_written_while_the_flag_is_off(monkeypatch: pytest.MonkeyPatch) -> None:
    result_id = str(uuid.uuid4())
    conn = _conn(result_id, style_memory_on=False)
    _install(monkeypatch, conn)
    client.post(
        f"/v1/tryon/results/{result_id}/feedback",
        json={"outcome": "rejected", "reason": "color_issue"},
        headers=_auth(),
    )
    assert not any("style_memory_signals" in sql for _m, sql, _a in conn.calls)
