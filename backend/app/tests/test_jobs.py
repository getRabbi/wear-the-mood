import importlib
from pathlib import Path

import yaml

from app.cron.daily import main as cron_main


def test_entrypoints_import() -> None:
    importlib.import_module("app.workers.worker")
    importlib.import_module("app.cron.daily")


def test_cron_main_runs() -> None:
    # No SENTRY_DSN configured -> sentry no-ops; should just log and return.
    cron_main()


def test_render_blueprint_parses_and_has_services() -> None:
    path = Path(__file__).resolve().parents[3] / "render.yaml"
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    names = {service["name"] for service in data["services"]}
    assert {"fashionos-api", "fashionos-worker", "fashionos-daily"} <= names
