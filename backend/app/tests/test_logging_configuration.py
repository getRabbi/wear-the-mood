"""The web app must actually apply ``settings.log_level`` (2026-07-30).

`log_level` was defined in Settings and consumed nowhere. Every cron and worker
called `logging.basicConfig` itself; the web app never did, so the root logger sat
at Python's default WARNING and every `log.info(...)` in the routers was discarded.

The cost was not cosmetic. The local-cutout handler measures download_ms,
compose_ms, store_ms and db_ms on every ingest and logs them at INFO — so the one
record that says WHERE a 7-9 second request spent its time had never been emitted
in production. Instrumentation existed; nobody could see it.
"""

import logging

import pytest

from app.core.config import Settings
from app.main import configure_logging


@pytest.fixture(autouse=True)
def _restore_root_logger():
    root = logging.getLogger()
    level, handlers = root.level, list(root.handlers)
    yield
    root.setLevel(level)
    root.handlers = handlers


@pytest.mark.parametrize(
    ("configured", "expected"),
    [
        ("INFO", logging.INFO),
        ("info", logging.INFO),
        (" Debug ", logging.DEBUG),
        ("WARNING", logging.WARNING),
        ("ERROR", logging.ERROR),
    ],
)
def test_the_configured_level_is_applied(configured: str, expected: int) -> None:
    applied = configure_logging(Settings(log_level=configured))
    assert applied == expected
    assert logging.getLogger().level == expected


def test_an_unknown_level_falls_back_to_info_rather_than_silence() -> None:
    # A typo must not mute the app. INFO is the documented default, and losing
    # observability to a bad string is exactly the failure this module prevents.
    assert configure_logging(Settings(log_level="verbose")) == logging.INFO


def test_router_info_records_are_actually_emitted() -> None:
    # NOTE: this deliberately does not use `caplog`. configure_logging passes
    # force=True, which detaches every existing root handler -- including the one
    # pytest installs for caplog -- so caplog would report nothing even though the
    # record really was emitted. Attach a handler AFTER configuring instead, which
    # is also closer to what production does.
    configure_logging(Settings(log_level="INFO"))

    captured: list[logging.LogRecord] = []

    class _Collector(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            captured.append(record)

    handler = _Collector()
    logging.getLogger().addHandler(handler)
    try:
        log = logging.getLogger("fashionos.wardrobe")
        assert log.isEnabledFor(logging.INFO)
        log.info("local cutout ingested download_ms=1 compose_ms=2 store_ms=3")
    finally:
        logging.getLogger().removeHandler(handler)

    assert any("local cutout ingested" in r.getMessage() for r in captured)


def test_warning_level_would_have_hidden_the_stage_timings() -> None:
    # The exact production state before this fix: the timings were computed and
    # logged, and no one could ever see them.
    configure_logging(Settings(log_level="WARNING"))
    assert not logging.getLogger("fashionos.wardrobe").isEnabledFor(logging.INFO)


def test_it_overrides_handlers_installed_earlier() -> None:
    # uvicorn installs its own handlers before create_app runs; without force=True
    # basicConfig is a silent no-op and the level stays at WARNING.
    logging.basicConfig(level=logging.WARNING, force=True)
    assert logging.getLogger().level == logging.WARNING

    configure_logging(Settings(log_level="INFO"))

    assert logging.getLogger().level == logging.INFO
