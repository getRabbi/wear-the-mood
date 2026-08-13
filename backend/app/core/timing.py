"""Stage timing for the try-on pipeline (CLAUDE.md §14).

Answers one question with evidence instead of opinion: *where do the 1-2 minutes
actually go*. A logical try-on spans three processes — the app, the submit
endpoint, and a scale-to-zero worker — so the only way to read it as one story is
a shared correlation token and the same log shape everywhere.

PRIVACY (§10, §11, §14). A stage timer records DURATIONS, COUNTS and BYTE SIZES.
It must never be handed an image, a base64 payload, a signed or unsigned media
URL, a token, an email, or anything else that identifies a person. `mark()` takes
a stage name from a fixed vocabulary and an optional integer, and there is
deliberately no free-text field to smuggle one of those into.

The correlation token is the first 8 hex characters of the request's idempotency
key. That is enough to stitch the three processes together in a log search and
far too little to replay a request with.

Overhead is a `time.monotonic()` call and a list append per stage, plus one log
line per process. Nothing here performs I/O, and nothing here creates a job, a
request, or a database round trip.
"""

from __future__ import annotations

import logging
import time
from contextvars import ContextVar
from dataclasses import dataclass, field

log = logging.getLogger("fashionos.timing")

#: Length of the correlation token taken from the idempotency key.
TRACE_TOKEN_CHARS = 8


def trace_token(idempotency_key: str | None) -> str:
    """A short, non-identifying correlation token.

    Deliberately a PREFIX: it correlates the app, the submit endpoint and the
    worker in a log search, and it cannot be used to replay the request.
    """
    if not idempotency_key:
        return "none"
    cleaned = "".join(ch for ch in idempotency_key if ch.isalnum())
    return cleaned[:TRACE_TOKEN_CHARS].lower() or "none"


@dataclass
class StageTimer:
    """Elapsed time per named stage of one logical operation.

    Not thread-safe and not meant to be: one timer belongs to one request or one
    job, start to finish.
    """

    #: What is being timed, e.g. `tryon.submit`. Appears in the log line.
    scope: str
    #: The correlation token shared with the app and the worker.
    trace: str
    _started: float = field(default_factory=time.monotonic)
    _last: float = field(default_factory=time.monotonic)
    _marks: list[tuple[str, int, int | None]] = field(default_factory=list)

    def mark(self, stage: str, value: int | None = None) -> int:
        """Record the milliseconds since the previous mark and return them.

        [value] is an optional integer for the stage — a byte size, an image
        count, a retry count. Never a string, and never anything derived from
        user content.
        """
        now = time.monotonic()
        elapsed_ms = int((now - self._last) * 1000)
        self._last = now
        self._marks.append((stage, elapsed_ms, value))
        return elapsed_ms

    @property
    def total_ms(self) -> int:
        return int((time.monotonic() - self._started) * 1000)

    def render(self) -> str:
        """One copyable line: `scope trace=ab12cd34 total=1234ms a=100 b=900`."""
        parts = [
            f"{stage}={ms}ms" + (f"({value})" if value is not None else "")
            for stage, ms, value in self._marks
        ]
        return f"{self.scope} trace={self.trace} total={self.total_ms}ms " + " ".join(parts)

    def emit(self) -> None:
        """Log the line. Safe to call once per operation, on every exit path."""
        log.info("%s", self.render())


#: The timer for the operation running on THIS task, so a helper deep in the
#: stack (the FASHN provider, the storage layer) can contribute a stage without
#: every signature between here and there growing a parameter it does not use.
#: None outside a timed operation, which every call site treats as "do nothing".
current_timer: ContextVar[StageTimer | None] = ContextVar("wtm_stage_timer", default=None)


def mark(stage: str, value: int | None = None) -> None:
    """Record a stage on the ambient timer, if there is one. Never raises."""
    timer = current_timer.get()
    if timer is not None:
        timer.mark(stage, value)
