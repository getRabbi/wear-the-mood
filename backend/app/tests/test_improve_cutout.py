"""Free user-requested BiRefNet improvement (local BG §6.4).

"Improve edges" re-runs the automatic cutout on a piece the user is not happy
with. The properties defended here, in order of how much damage getting them
wrong would do:

  * the CURRENT cutout stays live for the whole round trip, and still stands if
    the worker fails — a user must never lose a good cutout by asking for a
    better one;
  * `attempt_count` is reset, or the worker fails the row instantly on its
    max-attempts check;
  * duplicate taps never create concurrent work for the same row;
  * it is free — no credits, no membership, no AI beyond the existing worker;
  * the wake signal follows the existing best-effort + recovery semantics.
"""

from __future__ import annotations

import time
import uuid

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.routers.v1 import wardrobe as mod

from .test_local_cutout import _COLUMN_ROW, _Conn, _wire  # shared harness

TEST_SECRET = "test-jwt-secret-for-unit-tests-0123456789abcdef"
USER_ID = "user-123"
ITEM_ID = "11111111-1111-1111-1111-111111111111"

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


def _enable(monkeypatch: pytest.MonkeyPatch, *, gate: bool = True) -> None:
    monkeypatch.setenv("LOCAL_CUTOUT_IMPROVE_ENABLED", "true" if gate else "false")
    get_settings.cache_clear()


def _row(**overrides: object) -> dict:
    row = dict(_COLUMN_ROW)
    row["id"] = ITEM_ID
    row.update(overrides)
    return row


def _handlers(
    *,
    current: dict | None,
    requeued: dict | None,
) -> list[tuple[str, str, object]]:
    """`current` is the ownership fetch; `requeued` is the guarded UPDATE (None =
    the guard matched no row, i.e. an attempt is already in flight)."""
    return [
        ("fetchval", "app_rate_limit", True),
        ("fetchrow", "update public.wardrobe_items", requeued),
        ("fetchrow", "select id, title", current),
        ("fetch", "from public.media_assets", []),
    ]


def _url(item_id: str = ITEM_ID) -> str:
    return f"/v1/wardrobe/{item_id}/improve-cutout"


# ── gates and ownership ──────────────────────────────────────────────────────


def test_requires_a_token() -> None:
    resp = client.post(_url())
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


def test_gate_off_returns_404(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LOCAL_CUTOUT_IMPROVE_ENABLED", raising=False)
    get_settings.cache_clear()
    resp = client.post(_url(), headers=_auth())
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"


def test_ownership_is_enforced_with_404(monkeypatch: pytest.MonkeyPatch) -> None:
    # Not the caller's item (or missing) — 404 either way, never a hint.
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=None, requeued=None))
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 404
    assert conn.sql_calls("update public.wardrobe_items") == []
    assert signals == []


def test_item_without_a_source_image_is_422(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=_row(image_url=None), requeued=None))
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 422
    assert conn.sql_calls("update public.wardrobe_items") == []
    assert signals == []


# ── the money property: the existing cutout survives ─────────────────────────


def test_requeue_leaves_the_current_cutout_and_media_untouched(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The UPDATE must not clear cutout_url/thumbnail_url, and must not touch
    media_assets — that is what keeps the old cutout on screen while the new one
    is computed, and what keeps it there if the worker fails."""
    _enable(monkeypatch)
    current = _row(cutout_status="done", cutout_url="uid/cutout/old.png")
    # The real UPDATE ... RETURNING gives back the post-update row, and since
    # cutout_url is not in the SET clause it still holds the OLD cutout. The fake
    # mirrors that, which is the whole point being asserted.
    requeued = _row(cutout_status="queued", cutout_url="uid/cutout/old.png")
    conn = _Conn(_handlers(current=current, requeued=requeued))
    _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 202
    # Only the SET clause matters: cutout_url legitimately appears in RETURNING,
    # which is how the response carries the OLD cutout back to the client.
    update = conn.sql_calls("update public.wardrobe_items")[0][1]
    set_clause = update.split("returning")[0]
    assert "cutout_url" not in set_clause
    assert "thumbnail_url" not in set_clause
    assert conn.sql_calls("insert into public.media_assets") == []
    assert conn.sql_calls("update public.media_assets") == []
    # The response still carries the OLD cutout, so the client keeps rendering it.
    assert resp.json()["cutout_url"] == "uid/cutout/old.png"


def test_requeue_resets_exactly_the_fields_a_new_attempt_needs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(
        _handlers(current=_row(), requeued=_row(cutout_status="queued")),
    )
    _wire(monkeypatch, conn)

    client.post(_url(), headers=_auth())

    update = conn.sql_calls("update public.wardrobe_items")[0][1]
    # attempt_count reset is MANDATORY: the worker fails a row outright when
    # attempt_count > max_attempts, so without this the user's tap would mark the
    # item failed immediately.
    assert "attempt_count = 0" in update
    assert "cutout_locked_at = null" in update
    assert "cutout_last_signal_at = null" in update
    assert "cutout_error_code = null" in update
    assert "cutout_status = 'queued'" in update


def test_a_previously_failed_item_can_be_improved(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # The most likely real trigger: the automatic cutout failed, the user retries.
    _enable(monkeypatch)
    conn = _Conn(
        _handlers(
            current=_row(cutout_status="failed", cutout_url="uid/cutout/old.png"),
            requeued=_row(cutout_status="queued"),
        )
    )
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 202
    assert len(conn.sql_calls("update public.wardrobe_items")) >= 1
    assert [kind for kind, _ in signals] == ["rembg"]


# ── duplicate taps ───────────────────────────────────────────────────────────


def test_duplicate_tap_while_in_flight_creates_no_work(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The status guard in the UPDATE is the duplicate-tap guard: a second tap
    matches no row, so no second attempt and no second signal."""
    _enable(monkeypatch)
    current = _row(cutout_status="processing", cutout_url="uid/cutout/old.png")
    conn = _Conn(_handlers(current=current, requeued=None))
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 202  # idempotent-ish: the current item comes back
    assert resp.json()["cutout_status"] == "processing"
    assert signals == [], "no second wake signal for a row already in flight"


def test_the_guard_excludes_queued_and_processing_only(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=_row(), requeued=_row(cutout_status="queued")))
    _wire(monkeypatch, conn)

    client.post(_url(), headers=_auth())

    update = conn.sql_calls("update public.wardrobe_items")[0][1]
    assert "not in ('queued', 'processing')" in update


# ── free, and rate limited ───────────────────────────────────────────────────


def test_costs_nothing_and_checks_no_membership(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=_row(), requeued=_row(cutout_status="queued")))
    _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 202
    touched = [
        c
        for c in conn.calls
        if "credits" in c[1] or "entitlement" in c[1] or "ai_usage_log" in c[1]
    ]
    assert touched == [], "improvement spends nothing and logs no AI usage"


def test_is_rate_limited(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    handlers = _handlers(current=_row(), requeued=_row(cutout_status="queued"))
    handlers[0] = ("fetchval", "app_rate_limit", False)  # limiter says no
    conn = _Conn(handlers)
    _r2, signals = _wire(monkeypatch, conn)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 429
    assert resp.json()["error"]["code"] == "RATE_LIMITED"
    assert conn.sql_calls("update public.wardrobe_items") == []
    assert signals == []


# ── queue + recovery semantics ───────────────────────────────────────────────


def test_signals_the_rembg_worker_after_commit(monkeypatch: pytest.MonkeyPatch) -> None:
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=_row(), requeued=_row(cutout_status="queued")))
    _r2, signals = _wire(monkeypatch, conn)

    client.post(_url(), headers=_auth())

    assert [kind for kind, _ in signals] == ["rembg"]
    assert signals[0][1] == ITEM_ID
    # Stamped only after a SUCCESSFUL enqueue.
    assert any("cutout_last_signal_at = now()" in c[1] for c in conn.calls)


def test_a_failed_enqueue_leaves_the_signal_null_for_recovery(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """`enqueue_signal` is best-effort. When it fails the row must stay
    `cutout_last_signal_at = NULL` so recovery's stranded-queued scan heals it —
    the same backstop the normal create path relies on."""
    _enable(monkeypatch)
    conn = _Conn(_handlers(current=_row(), requeued=_row(cutout_status="queued")))

    async def _no_enqueue(kind: str, job_id: str, **kw: object) -> bool:
        return False

    _wire(monkeypatch, conn)
    monkeypatch.setattr(mod, "enqueue_signal", _no_enqueue)

    resp = client.post(_url(), headers=_auth())

    assert resp.status_code == 202
    assert not any("cutout_last_signal_at = now()" in c[1] for c in conn.calls)


# ── the editor stays a separate, unaffected tool ─────────────────────────────


def test_the_improvement_gate_does_not_expose_the_editor(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Improve edges (automatic re-run) and Fix cutout (manual editor) are
    different features with different gates; enabling one must not expose the
    other."""
    _enable(monkeypatch)
    monkeypatch.delenv("CUTOUT_EDITOR_ENABLED", raising=False)
    get_settings.cache_clear()

    import io

    from PIL import Image

    buf = io.BytesIO()
    Image.new("L", (8, 8), 128).save(buf, format="PNG")
    resp = client.put(
        f"/v1/wardrobe/{uuid.uuid4()}/cutout-mask",
        files={"mask": ("m.png", buf.getvalue(), "image/png")},
        headers=_auth(),
    )
    assert resp.status_code == 404


def test_the_editor_gate_does_not_expose_the_improvement(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("CUTOUT_EDITOR_ENABLED", "true")
    monkeypatch.delenv("LOCAL_CUTOUT_IMPROVE_ENABLED", raising=False)
    get_settings.cache_clear()

    resp = client.post(_url(), headers=_auth())
    assert resp.status_code == 404
