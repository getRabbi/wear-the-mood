"""Server-side flag helper (Phase 4B · B2 kill-switch)."""

from __future__ import annotations

import asyncio

from app.core.flags import flag_enabled


class _Conn:
    def __init__(self, value: object) -> None:
        self.value = value

    async def fetchval(self, sql: str, *a: object) -> object:
        return self.value


def test_flag_enabled_returns_row_value() -> None:
    assert asyncio.run(flag_enabled(_Conn(True), "ai_tryon_enabled", default=False)) is True
    assert asyncio.run(flag_enabled(_Conn(False), "ai_tryon_enabled", default=True)) is False


def test_flag_absent_uses_default() -> None:
    assert asyncio.run(flag_enabled(_Conn(None), "x", default=True)) is True
    assert asyncio.run(flag_enabled(_Conn(None), "x", default=False)) is False
