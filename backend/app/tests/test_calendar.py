"""Calendar autopilot (CLAUDE.md §24) — request validation, auth, live SQL."""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.calendar import CalendarEvent, CalendarPlanRequest

client = TestClient(app)


# ── request validation ───────────────────────────────────────────────────────


def test_event_requires_title() -> None:
    with pytest.raises(ValueError):
        CalendarEvent(title="")


def test_request_requires_at_least_one_event() -> None:
    with pytest.raises(ValueError):
        CalendarPlanRequest(events=[])


def test_request_caps_the_batch() -> None:
    events = [CalendarEvent(title=f"Event {i}") for i in range(13)]
    with pytest.raises(ValueError):
        CalendarPlanRequest(events=events)


def test_request_accepts_a_normal_batch() -> None:
    req = CalendarPlanRequest(
        events=[
            CalendarEvent(title="Team meeting", occasion="work"),
            CalendarEvent(title="Dinner with friends"),
        ]
    )
    assert len(req.events) == 2


# ── auth gate ────────────────────────────────────────────────────────────────


def test_plan_requires_token() -> None:
    resp = client.post("/v1/calendar/plan", json={"events": [{"title": "Standup"}]})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_calendar_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.wardrobe import _COLUMNS

    stmts = [
        f"select {_COLUMNS} from public.wardrobe_items "
        "where user_id = $1::uuid order by created_at desc limit 200",
        "insert into public.ai_usage_log "
        "(user_id, provider, task, input_tokens, output_tokens, images, "
        "estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, 'calendar', $3, $4, 0, $5, $6, $7)",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
