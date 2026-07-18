"""app.tasks.* one-shot wrappers import cleanly and expose a callable main (§11.7)."""

from __future__ import annotations

import importlib

import pytest

# The six converted crons + the recovery task, all under app.tasks.* (§11.6, §11.7).
_TASKS = ["news", "daily", "backup", "spend_alert", "credit_reset", "giveaway_chats", "recovery"]


@pytest.mark.parametrize("name", _TASKS)
def test_task_module_has_callable_main(name: str) -> None:
    mod = importlib.import_module(f"app.tasks.{name}")
    assert callable(mod.main)


@pytest.mark.parametrize(
    "name", ["news", "daily", "backup", "spend_alert", "credit_reset", "giveaway_chats"]
)
def test_wrapper_reexports_cron_main(name: str) -> None:
    task = importlib.import_module(f"app.tasks.{name}")
    cron = importlib.import_module(f"app.cron.{name}")
    assert task.main is cron.main  # thin wrapper: same callable, DO ofelia unaffected
