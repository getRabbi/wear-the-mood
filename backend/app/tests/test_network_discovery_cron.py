"""When the discovery cron talks to the network, and when it stays quiet.

The scheduler ticks far more often than an advertiser list changes, because the
tick rate is what decides how long an operator waits after pressing "Re-scan
network". That makes the tick the wrong unit for deciding to call the partner
API, and these tests pin the separation: admin requests are always served
immediately, unprompted listings are rate-limited by age, and the two never
happen in the same tick.

The gate is asserted as SQL — the age comparison belongs to the database clock,
so a test that compared datetimes in the process would be testing the wrong
thing.
"""

from __future__ import annotations

import asyncio
from typing import Any

import pytest

from app.cron import network_discovery as cron


class FakeConn:
    """Records SQL; answers the two questions the cron asks."""

    def __init__(self, *, claims: list[dict[str, Any]] | None = None, due: bool = True) -> None:
        self.sql: list[str] = []
        self.params: list[tuple[Any, ...]] = []
        self._claims = list(claims or [])
        self._due = due

    async def fetchrow(self, query: str, *args: Any) -> Any:
        self.sql.append(" ".join(query.split()))
        self.params.append(args)
        if "claim_queued_network_discovery" in query:
            return self._claims.pop(0) if self._claims else None
        return None

    async def fetchval(self, query: str, *args: Any) -> Any:
        self.sql.append(" ".join(query.split()))
        self.params.append(args)
        if "network_discovery_runs" in query and "not exists" in query:
            return self._due
        return None

    async def execute(self, query: str, *args: Any) -> str:
        self.sql.append(" ".join(query.split()))
        self.params.append(args)
        return "OK"

    def find(self, needle: str) -> list[str]:
        return [q for q in self.sql if needle in q]


class _Acquire:
    def __init__(self, conn: FakeConn) -> None:
        self._conn = conn

    async def __aenter__(self) -> FakeConn:
        return self._conn

    async def __aexit__(self, *_: Any) -> bool:
        return False


class _Pool:
    def __init__(self, conn: FakeConn) -> None:
        self._conn = conn

    def acquire(self) -> _Acquire:
        return _Acquire(self._conn)


@pytest.fixture
def wire(monkeypatch: pytest.MonkeyPatch):
    """Run the cron against a fake DB, recording every discovery call."""

    def _wire(conn: FakeConn, *, flag: bool = True) -> list[dict[str, Any]]:
        calls: list[dict[str, Any]] = []

        async def fake_init_db() -> bool:
            return True

        async def fake_close_db() -> None:
            return None

        async def fake_flag(_conn: Any, key: str, default: bool = False) -> bool:
            assert key == "feature_network_discovery"
            return flag

        async def fake_discover(_conn: Any, **kwargs: Any) -> dict[str, Any]:
            calls.append(kwargs)
            return {"status": "success", "listing_complete": True}

        monkeypatch.setattr(cron, "init_db", fake_init_db)
        monkeypatch.setattr(cron, "close_db", fake_close_db)
        monkeypatch.setattr(cron, "get_pool", lambda: _Pool(conn))
        monkeypatch.setattr(cron, "flag_enabled", fake_flag)
        monkeypatch.setattr(cron, "discover_awin", fake_discover)
        return calls

    return _wire


def _run() -> None:
    asyncio.run(cron._run())


# ── the flag still wins ─────────────────────────────────────────────────────


def test_the_flag_off_reaches_no_network(wire) -> None:
    conn = FakeConn()
    calls = wire(conn, flag=False)
    _run()
    assert calls == []
    # Not even the due check runs — an off switch should cost nothing.
    assert conn.find("network_discovery_runs") == []


# ── the due gate ────────────────────────────────────────────────────────────


def test_an_unprompted_listing_waits_for_the_interval(wire) -> None:
    conn = FakeConn(due=False)
    calls = wire(conn)
    _run()
    assert calls == [], "a tick inside the interval must not call the network"


def test_an_unprompted_listing_runs_once_due(wire) -> None:
    conn = FakeConn(due=True)
    calls = wire(conn)
    _run()
    assert len(calls) == 1
    assert calls[0]["trigger_source"] == "cron"


def test_the_gate_asks_the_database_for_the_age(wire) -> None:
    # Clock skew between a container and the database must not be able to open
    # or close this gate, so the comparison is server-side.
    conn = FakeConn(due=True)
    wire(conn)
    _run()
    gate = conn.find("not exists")
    assert gate, "expected a due-check query"
    assert "now() -" in gate[0] and "make_interval" in gate[0]
    assert "trigger_source = 'cron'" in gate[0]


def test_the_gate_counts_attempts_not_successes(wire) -> None:
    # A failing network is exactly when retrying every tick does most damage.
    conn = FakeConn(due=True)
    wire(conn)
    _run()
    gate = conn.find("not exists")[0]
    assert "status" not in gate, "the gate must not filter on run status"


def test_the_interval_is_hours_not_minutes(wire) -> None:
    conn = FakeConn(due=True)
    wire(conn)
    _run()
    args = [p for q, p in zip(conn.sql, conn.params, strict=True) if "not exists" in q][0]
    assert args == ("awin", 12)


# ── admin requests outrank, and suppress, the scheduled pass ────────────────


def test_an_admin_request_is_served_in_the_same_tick(wire) -> None:
    conn = FakeConn(claims=[{"run_id": "r1", "network": "awin", "triggered_by": "admin@x"}])
    calls = wire(conn)
    _run()
    assert len(calls) == 1
    assert calls[0]["trigger_source"] == "admin"
    assert calls[0]["run_id"] == "r1"


def test_an_admin_request_suppresses_the_second_listing(wire) -> None:
    # Two listings of the same account in one tick tell you the same thing twice.
    conn = FakeConn(claims=[{"run_id": "r1", "network": "awin", "triggered_by": "a"}], due=True)
    calls = wire(conn)
    _run()
    assert len(calls) == 1, "an admin pass must not be followed by a cron pass"
    assert conn.find("not exists") == [], "the due check is not even reached"


def test_an_admin_request_ignores_the_interval(wire) -> None:
    # The button is the escape hatch from the gate; if it were also rate-limited
    # a failing network would be unrecoverable for 12 hours.
    conn = FakeConn(claims=[{"run_id": "r1", "network": "awin", "triggered_by": "a"}], due=False)
    calls = wire(conn)
    _run()
    assert len(calls) == 1


def test_a_network_with_no_connector_is_closed_not_left_running(wire) -> None:
    conn = FakeConn(claims=[{"run_id": "r9", "network": "rakuten", "triggered_by": "a"}])
    calls = wire(conn)
    _run()
    assert calls == []
    closed = conn.find("update public.network_discovery_runs")
    assert closed and "status = 'failed'" in closed[0]


# ── the interval setting ────────────────────────────────────────────────────


def test_the_interval_is_env_tunable(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("NETWORK_DISCOVERY_INTERVAL_HOURS", "6")
    assert cron._scheduled_interval_hours() == 6


@pytest.mark.parametrize("bad", ["0", "-1", "not-a-number", ""])
def test_a_disabling_interval_falls_back_to_the_default(
    monkeypatch: pytest.MonkeyPatch, bad: str
) -> None:
    # 0 or negative would mean "list every tick" — the cost failure the gate
    # exists to prevent. It must not be reachable by configuration.
    monkeypatch.setenv("NETWORK_DISCOVERY_INTERVAL_HOURS", bad)
    assert cron._scheduled_interval_hours() == 12
