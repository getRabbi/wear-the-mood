"""Versioned wake-signal messages for the Azure Storage Queue bridge (blueprint §4.3).

Queue messages are **wake-up + scale signals only** — never the authoritative job
record. Postgres remains the source of truth (§4.2). A message therefore carries no
secrets, user images, signed URLs, prompts, or personal data (§4.3) — just enough to
wake a worker and let it claim the referenced DB row.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime

# Bump only with a compatible reader; consumers reject other versions (§4.4 step 2).
MESSAGE_VERSION = 1

# `kind` values that must at least be distinguished (§4.3).
KIND_REMBG = "rembg"
KIND_ENRICHMENT = "enrichment"
KIND_TRYON = "tryon"
ALLOWED_KINDS = frozenset({KIND_REMBG, KIND_ENRICHMENT, KIND_TRYON})


class QueueMessageError(ValueError):
    """Raised when a message fails schema/version validation (§4.4 step 2)."""


@dataclass(frozen=True)
class QueueMessage:
    """Small versioned JSON wake signal (§4.3)."""

    kind: str
    job_id: str
    enqueued_at: str  # RFC3339 / ISO-8601 UTC
    trace_id: str
    v: int = MESSAGE_VERSION

    @staticmethod
    def new(kind: str, job_id: str, *, trace_id: str | None = None) -> QueueMessage:
        if kind not in ALLOWED_KINDS:
            raise QueueMessageError(f"unknown kind: {kind!r}")
        return QueueMessage(
            v=MESSAGE_VERSION,
            kind=kind,
            job_id=str(job_id),
            enqueued_at=datetime.now(UTC).isoformat(),
            trace_id=trace_id or uuid.uuid4().hex,
        )

    def to_json(self) -> str:
        return json.dumps(
            {
                "v": self.v,
                "kind": self.kind,
                "job_id": self.job_id,
                "enqueued_at": self.enqueued_at,
                "trace_id": self.trace_id,
            },
            separators=(",", ":"),
        )

    @staticmethod
    def from_json(raw: str | bytes) -> QueueMessage:
        try:
            data = json.loads(raw)
        except (ValueError, TypeError) as exc:
            raise QueueMessageError("invalid JSON") from exc
        if not isinstance(data, dict):
            raise QueueMessageError("message is not a JSON object")
        version = data.get("v")
        if version != MESSAGE_VERSION:
            raise QueueMessageError(f"unsupported message version: {version!r}")
        kind = data.get("kind")
        if kind not in ALLOWED_KINDS:
            raise QueueMessageError(f"unknown kind: {kind!r}")
        job_id = data.get("job_id")
        if not isinstance(job_id, str) or not job_id:
            raise QueueMessageError("missing/invalid job_id")
        return QueueMessage(
            v=version,
            kind=kind,
            job_id=job_id,
            enqueued_at=str(data.get("enqueued_at", "")),
            trace_id=str(data.get("trace_id", "")),
        )
