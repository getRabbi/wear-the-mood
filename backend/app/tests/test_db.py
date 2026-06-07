import asyncio

import pytest

from app.core.config import get_settings
from app.core.db import close_db, init_db, ping


def test_db_ping_when_configured() -> None:
    """Live connectivity check. Skips in environments without a DSN (e.g. CI)."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    async def run() -> None:
        assert await init_db() is True
        try:
            assert await ping() is True
        finally:
            await close_db()

    asyncio.run(run())


def test_init_db_noop_without_dsn(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("CONNECTION_STRING", "")
    get_settings.cache_clear()
    try:
        assert asyncio.run(init_db()) is False
    finally:
        get_settings.cache_clear()
