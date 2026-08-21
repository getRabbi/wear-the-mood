"""Event reminders — the three rules that keep this a reminder, not a channel.

1. Nothing is sent while `feature_event_planner` is off.
2. Each stage fires once, ever — the claim marks the row in the same statement
   that selects it, so a re-run cannot repeat a nudge.
3. It STOPS. Three stages exist and there is no fourth; nothing follows up on
   a user who did not open the app (§23: no guilt messaging).
"""

from __future__ import annotations

import asyncio

from app.cron.event_reminders import _COPY, _STAGES, run_event_reminders


class _FakeConn:
    """Answers the flag read and the three claim statements from a plan."""

    def __init__(self, *, enabled: bool = True, due: dict[str, list[dict]] | None = None):
        self.enabled = enabled
        self.due = due or {}
        self.claimed: list[str] = []
        self.notifications: list[dict] = []

    def transaction(self):
        class _Tx:
            async def __aenter__(self_):
                return self_

            async def __aexit__(self_, *_a):
                return False

        return _Tx()

    async def fetchval(self, sql: str, *args):
        if "feature_flags" in sql:
            return self.enabled
        return None

    async def fetch(self, sql: str, *args):
        stage = args[0]
        self.claimed.append(stage)
        # A claim CONSUMES the rows: the statement appends to `reminders_sent`,
        # so a second pass over the same stage finds nothing.
        return self.due.pop(stage, [])

    async def execute(self, sql: str, *args):
        return "OK"


def _event(name: str = "Nadia wedding") -> dict:
    return {
        "id": "11111111-1111-4111-8111-111111111111",
        "user_id": "22222222-2222-4222-8222-222222222222",
        "name": name,
        "event_at": None,
    }


def _run(conn: _FakeConn, monkeypatch) -> int:
    recorded: list[dict] = []

    async def _capture(_conn, **kwargs):
        recorded.append(kwargs)
        return None

    monkeypatch.setattr("app.cron.event_reminders.create_notification", _capture)
    count = asyncio.run(run_event_reminders(conn))  # type: ignore[arg-type]
    conn.notifications = recorded
    return count


def test_nothing_is_sent_while_the_flag_is_off(monkeypatch) -> None:
    conn = _FakeConn(enabled=False, due={"d7": [_event()]})
    assert _run(conn, monkeypatch) == 0
    assert conn.claimed == []  # not even a claim query ran
    assert conn.notifications == []


def test_a_due_event_is_reminded_once(monkeypatch) -> None:
    conn = _FakeConn(due={"d2": [_event()]})
    assert _run(conn, monkeypatch) == 1
    message = conn.notifications[0]
    assert "two days" in message["title"]
    assert message["dedupe_key"].endswith(":d2")
    assert message["target_type"] == "event"


def test_a_second_run_sends_nothing(monkeypatch) -> None:
    """The claim marked the row, so the next pass finds no due events."""
    conn = _FakeConn(due={"d7": [_event()]})
    assert _run(conn, monkeypatch) == 1
    assert _run(conn, monkeypatch) == 0


def test_every_stage_is_attempted_each_run(monkeypatch) -> None:
    conn = _FakeConn(due={})
    _run(conn, monkeypatch)
    assert conn.claimed == ["d7", "d2", "d0"]


def test_there_is_no_follow_up_after_the_day(monkeypatch) -> None:
    """Three stages, and the last one is the event itself. A 'you missed it'
    message would be exactly the guilt push §23 forbids."""
    assert [stage for stage, _, _ in _STAGES] == ["d7", "d2", "d0"]
    assert set(_COPY) == {"d7", "d2", "d0"}


def test_a_long_event_name_cannot_flood_a_lock_screen(monkeypatch) -> None:
    conn = _FakeConn(due={"d0": [_event(name="x" * 500)]})
    _run(conn, monkeypatch)
    assert len(conn.notifications[0]["title"]) < 100


def test_the_reminder_rides_the_users_style_category(monkeypatch) -> None:
    """It goes out as `daily_style`, so muting daily style mutes this too —
    a reminder must not be a category the user cannot switch off."""
    conn = _FakeConn(due={"d0": [_event()]})
    _run(conn, monkeypatch)
    assert conn.notifications[0]["type"] == "daily_style"
