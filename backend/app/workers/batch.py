"""Finite batch runner for event-driven Azure Container Apps **Jobs** (Phase 5 §A/B).

Why this exists
---------------
The first Azure design ran the workers as always-on Container **Apps** scaled on
queue depth. Phase 5 §14.5 measured that as the dominant cost driver: ACA bills
allocated resources for as long as a replica is alive, including the scale-down
cooldown, so once the job arrival gap fell below the cooldown a 2 vCPU / 4 GiB
replica was pinned on continuously — ~$150/month against a $16.67/month ceiling,
while the actual work was only ~$7.56/month.

Container Apps **Jobs** bill per execution instead. An execution wakes on a queue
event, drains a bounded batch, and exits — so idle time is never billed. That only
works if the entrypoint actually *terminates*, which the endless
``while True`` worker loop never did. This runner provides that termination.

Exit policy (all limits are env-tunable so they can be tuned from measurements):

* ``max_jobs``          — stop after this many signals are handled;
* ``max_seconds``       — stop after this wall-clock budget, checked between polls
                          so an in-flight job is never abandoned mid-write;
* ``idle_exit_seconds`` — stop once the queue has been continuously empty this long.

Draining several jobs per execution matters for cost: expensive one-time startup
(interpreter + model load) is amortised across the batch instead of being paid per
image. Do not drop to one image per execution without measuring — §B.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from typing import Protocol

import asyncpg

log = logging.getLogger("fashionos.worker.batch")

POLL_SLEEP_SECONDS = 1.0


class _RunOnce(Protocol):
    def __call__(
        self,
        conn: asyncpg.Connection,
        provider: object,
        *,
        stale_seconds: int,
        max_attempts: int,
    ) -> Awaitable[int]: ...


@dataclass
class BatchResult:
    """Summary of one Job execution — logged so cost/latency can be reconstructed."""

    processed: int = 0
    polls: int = 0
    elapsed_s: float = 0.0
    startup_s: float = 0.0
    reason: str = ""
    errors: int = 0
    per_job_s: list[float] = field(default_factory=list)

    def log(self, label: str) -> None:
        avg = sum(self.per_job_s) / len(self.per_job_s) if self.per_job_s else 0.0
        log.info(
            "%s batch done: processed=%d polls=%d elapsed=%.1fs startup=%.1fs "
            "avg_job=%.2fs errors=%d reason=%s",
            label, self.processed, self.polls, self.elapsed_s,
            self.startup_s, avg, self.errors, self.reason,
        )


async def run_batch(
    *,
    conn_factory: Callable[[], object],
    provider: object,
    run_once: _RunOnce,
    stale_seconds: int,
    max_attempts: int,
    max_jobs: int,
    max_seconds: float,
    idle_exit_seconds: float,
    label: str,
    startup_s: float = 0.0,
) -> BatchResult:
    """Drain the queue until a bounded exit condition is met, then return.

    ``conn_factory`` yields an async context manager for a pooled connection
    (``get_pool().acquire``), acquired per poll so a long batch never pins one.
    """
    res = BatchResult(startup_s=startup_s)
    t0 = time.monotonic()
    idle_since: float | None = None

    while True:
        elapsed = time.monotonic() - t0
        if res.processed >= max_jobs:
            res.reason = "max_jobs"
            break
        if elapsed >= max_seconds:
            res.reason = "max_seconds"
            break

        res.polls += 1
        n = 0
        poll_started = time.monotonic()
        try:
            async with conn_factory() as conn:  # type: ignore[attr-defined]
                n = await run_once(
                    conn, provider, stale_seconds=stale_seconds, max_attempts=max_attempts
                )
        except Exception:  # noqa: BLE001 - one bad poll must not kill the execution
            res.errors += 1
            log.exception("%s batch poll failed", label)
            n = 0

        if n:
            res.processed += n
            res.per_job_s.extend([(time.monotonic() - poll_started) / n] * n)
            idle_since = None
            continue  # work available -> drain immediately, no sleep

        # Queue empty: start (or continue) the idle countdown.
        now = time.monotonic()
        if idle_since is None:
            idle_since = now
        elif now - idle_since >= idle_exit_seconds:
            res.reason = "idle"
            break
        await asyncio.sleep(POLL_SLEEP_SECONDS)

    res.elapsed_s = time.monotonic() - t0
    res.log(label)
    return res
