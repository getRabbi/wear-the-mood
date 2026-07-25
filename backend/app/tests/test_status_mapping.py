"""External job-status mapping — old (internal) + new (external) states (blueprint §4.5, §11.10)."""

from __future__ import annotations

import pytest

from app.core.status import external_status
from app.models.ai_studio import AiJobResponse
from app.models.tryon import TryOnJobResponse


@pytest.mark.parametrize(
    ("internal", "external"),
    [
        ("queued", "queued"),
        ("preparing", "preparing"),
        ("processing", "processing"),
        ("done", "ready"),
        ("completed", "ready"),
        ("failed", "failed"),
        ("DONE", "ready"),  # case-insensitive
        ("weird", "queued"),  # unknown → safe default
        (None, "queued"),
    ],
)
def test_external_status_map(internal, external) -> None:
    assert external_status(internal) == external


def test_tryon_response_keeps_internal_status_and_adds_state() -> None:
    r = TryOnJobResponse(job_id="j", status="done")
    assert r.status == "done"  # legacy field unchanged (old clients)
    assert r.state == "ready"  # new external field
    assert TryOnJobResponse(job_id="j", status="queued").state == "queued"


def test_ai_response_maps_completed_to_ready() -> None:
    r = AiJobResponse(job_id="j", job_type="enhance_item", status="completed")
    assert r.status == "completed"
    assert r.state == "ready"


def test_explicit_state_is_not_overwritten() -> None:
    r = TryOnJobResponse(job_id="j", status="processing", state="custom")
    assert r.state == "custom"
