"""External job-status mapping (blueprint §4.5, §11.10).

Public API states: ``queued → preparing → processing → ready | failed``. The internal
per-table states (``done``/``completed``/…) stay in the DB and on the legacy ``status``
field; this maps them to the stable external ``state`` so new clients get one vocabulary
while old clients keep reading ``status`` unchanged.
"""

from __future__ import annotations

QUEUED = "queued"
PREPARING = "preparing"
PROCESSING = "processing"
READY = "ready"
FAILED = "failed"

EXTERNAL_STATES = (QUEUED, PREPARING, PROCESSING, READY, FAILED)

_MAP = {
    "queued": QUEUED,
    "preparing": PREPARING,
    "processing": PROCESSING,
    "done": READY,
    "completed": READY,
    "ready": READY,
    "failed": FAILED,
    "error": FAILED,
}


def external_status(internal: str | None) -> str:
    """Map an internal status to the external contract; unknown → 'queued' (safe default)."""
    return _MAP.get((internal or "").strip().lower(), QUEUED)
