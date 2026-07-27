"""Local-first background-removal runtime gates (Phase 1 — dormant).

Phase 1 adds the settings only; the endpoints arrive in Phases 2 and 6. What must
be true NOW is that the feature ships OFF: a deploy of this branch changes nothing
until an operator sets the env var, and the existing cloud BiRefNet path is
untouched. These tests are the guard against a default flipping by accident.
"""

from __future__ import annotations

import pytest

from app.core.config import get_settings


@pytest.fixture(autouse=True)
def _clear_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_local_cutout_gates_default_off(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LOCAL_CUTOUT_UPLOAD_ENABLED", raising=False)
    monkeypatch.delenv("LOCAL_CUTOUT_IMPROVE_ENABLED", raising=False)
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.local_cutout_upload_enabled is False
    assert settings.local_cutout_improve_enabled is False


def test_local_cutout_gates_are_independently_settable(monkeypatch: pytest.MonkeyPatch) -> None:
    # Rollout enables ingestion first and the improvement path separately (§7).
    monkeypatch.setenv("LOCAL_CUTOUT_UPLOAD_ENABLED", "true")
    monkeypatch.delenv("LOCAL_CUTOUT_IMPROVE_ENABLED", raising=False)
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.local_cutout_upload_enabled is True
    assert settings.local_cutout_improve_enabled is False


def test_local_gates_do_not_disturb_the_existing_bg_settings(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The BiRefNet fallback keeps its own knobs; turning the local feature on must
    not imply anything about the model, the mask pipeline or the editor (§2.2)."""
    monkeypatch.setenv("LOCAL_CUTOUT_UPLOAD_ENABLED", "true")
    monkeypatch.setenv("LOCAL_CUTOUT_IMPROVE_ENABLED", "true")
    monkeypatch.delenv("BG_MODEL", raising=False)
    monkeypatch.delenv("BG_MASK_PIPELINE_V2", raising=False)
    monkeypatch.delenv("CUTOUT_EDITOR_ENABLED", raising=False)
    get_settings.cache_clear()

    settings = get_settings()
    assert settings.bg_model == "u2net"  # repo default; prod sets birefnet-general-lite
    assert settings.bg_mask_pipeline_v2 is False
    assert settings.cutout_editor_enabled is False
