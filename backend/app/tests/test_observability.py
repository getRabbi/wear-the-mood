import pytest

from app.core.config import get_settings
from app.core.observability import init_sentry


def test_init_sentry_noop_without_dsn(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SENTRY_DSN", "")
    get_settings.cache_clear()
    try:
        assert init_sentry() is False
    finally:
        get_settings.cache_clear()
