"""AI-spend alert cron (Phase 4B · B2). Mocked DB — no network."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import app.cron.spend_alert as spend_alert


class _Conn:
    def __init__(self, total: object) -> None:
        self.total = total

    async def fetchval(self, sql: str, *a: object) -> object:
        return self.total


class _AcquireCtx:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _Conn:
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, total: float) -> None:
        self.conn = _Conn(total)

    def acquire(self) -> _AcquireCtx:
        return _AcquireCtx(self.conn)


def test_spend_query_coerces_float() -> None:
    assert asyncio.run(spend_alert._spend_last_24h(_Conn(12.5))) == 12.5
    assert asyncio.run(spend_alert._spend_last_24h(_Conn(None))) == 0.0


def _wire(monkeypatch, total: float, threshold: float, calls: list) -> None:
    async def _true() -> bool:
        return True

    async def _none() -> None:
        return None

    monkeypatch.setattr(spend_alert, "init_db", _true)
    monkeypatch.setattr(spend_alert, "close_db", _none)
    monkeypatch.setattr(spend_alert, "get_pool", lambda: _Pool(total))
    monkeypatch.setattr(
        spend_alert, "get_settings", lambda: SimpleNamespace(daily_cost_alert_usd=threshold)
    )
    monkeypatch.setattr(spend_alert, "_alert", lambda s, t: calls.append((s, t)))


def test_alert_fires_at_or_over_threshold(monkeypatch) -> None:
    calls: list = []
    _wire(monkeypatch, total=30.0, threshold=25.0, calls=calls)
    asyncio.run(spend_alert._run())
    assert calls == [(30.0, 25.0)]


def test_no_alert_under_threshold(monkeypatch) -> None:
    calls: list = []
    _wire(monkeypatch, total=10.0, threshold=25.0, calls=calls)
    asyncio.run(spend_alert._run())
    assert calls == []


def test_threshold_zero_disables_alert(monkeypatch) -> None:
    calls: list = []
    _wire(monkeypatch, total=999.0, threshold=0.0, calls=calls)
    asyncio.run(spend_alert._run())
    assert calls == []
