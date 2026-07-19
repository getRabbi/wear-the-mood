"""Tests for the finite batch runner used by the event-driven Container Apps Jobs
(Phase 5 §B).

The whole point of the Jobs migration is that an execution TERMINATES — an
execution that never exits is billed like the always-on Container App it replaced.
So every exit condition is asserted here.
"""

from __future__ import annotations

import asyncio
import contextlib

import pytest

from app.workers.batch import run_batch


class _Conn:
    pass


@contextlib.asynccontextmanager
async def _conn_factory():
    yield _Conn()


def _run(**kw):
    base = dict(
        conn_factory=_conn_factory,
        provider=object(),
        stale_seconds=300,
        max_attempts=5,
        max_jobs=10,
        max_seconds=180,
        idle_exit_seconds=0.05,
        label="test",
    )
    base.update(kw)
    return asyncio.run(run_batch(**base))


def test_exits_when_queue_stays_empty() -> None:
    """No work at all -> exit on the idle timer, not a hang."""
    async def never_any_work(conn, provider, *, stale_seconds, max_attempts):
        return 0

    res = _run(run_once=never_any_work)
    assert res.reason == "idle"
    assert res.processed == 0
    assert res.polls >= 1


def test_stops_at_max_jobs() -> None:
    """A busy queue must still bound the execution."""
    async def always_one(conn, provider, *, stale_seconds, max_attempts):
        return 1

    res = _run(run_once=always_one, max_jobs=4)
    assert res.reason == "max_jobs"
    assert res.processed == 4


def test_stops_at_max_seconds() -> None:
    """The wall-clock budget bounds an execution even while work keeps arriving."""
    async def slow_work(conn, provider, *, stale_seconds, max_attempts):
        await asyncio.sleep(0.02)
        return 1

    res = _run(run_once=slow_work, max_jobs=10_000, max_seconds=0.1)
    assert res.reason == "max_seconds"
    assert res.elapsed_s >= 0.1


def test_idle_timer_resets_when_work_arrives() -> None:
    """A quiet gap mid-batch must not end the execution while work is still coming."""
    state = {"n": 0}

    async def gappy(conn, provider, *, stale_seconds, max_attempts):
        state["n"] += 1
        return 0 if state["n"] in (2, 3) else 1

    res = _run(run_once=gappy, max_jobs=3, idle_exit_seconds=5.0)
    assert res.reason == "max_jobs"
    assert res.processed == 3


def test_poll_error_does_not_kill_execution() -> None:
    """One bad poll is counted and retried, not allowed to abort the batch —
    otherwise a transient DB blip would strand the rest of the queue."""
    state = {"n": 0}

    async def flaky(conn, provider, *, stale_seconds, max_attempts):
        state["n"] += 1
        if state["n"] == 1:
            raise RuntimeError("transient")
        return 1

    res = _run(run_once=flaky, max_jobs=2)
    assert res.errors == 1
    assert res.processed == 2
    assert res.reason == "max_jobs"


def test_result_records_startup_for_cost_accounting() -> None:
    """startup_s must survive into the summary: the §14.5 cost model needs
    model-load overhead counted, not just processing time."""
    async def none(conn, provider, *, stale_seconds, max_attempts):
        return 0

    res = _run(run_once=none, startup_s=12.5)
    assert res.startup_s == 12.5


@pytest.mark.parametrize("max_jobs", [1, 5, 20])
def test_batch_size_is_parameterised(max_jobs: int) -> None:
    """§B requires the limits be tunable from measured results."""
    async def always_one(conn, provider, *, stale_seconds, max_attempts):
        return 1

    assert _run(run_once=always_one, max_jobs=max_jobs).processed == max_jobs


def test_settings_expose_tunable_batch_policy() -> None:
    from app.core.config import get_settings

    s = get_settings()
    assert s.rembg_batch_max_jobs == 10
    assert s.orchestrator_batch_max_jobs == 20
    assert s.batch_max_seconds == 180
    assert s.batch_idle_exit_seconds == 10


def test_all_polls_failing_is_reported_as_failure() -> None:
    """An execution that errors on every poll and processes nothing must be
    distinguishable from a drained queue. Returning success there masked a fully
    broken environment as 'Succeeded' during Phase 5 Job testing."""
    async def always_raises(conn, provider, *, stale_seconds, max_attempts):
        raise RuntimeError("environment is broken")

    res = _run(run_once=always_raises, idle_exit_seconds=0.05)
    assert res.processed == 0
    assert res.errors >= 1  # the caller maps this combination to a non-zero exit
