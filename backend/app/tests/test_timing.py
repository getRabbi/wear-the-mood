"""Stage timing for the try-on pipeline (CLAUDE.md §14).

The tool exists to answer "where do the 1-2 minutes go" with evidence. So the
two things worth pinning are that it correlates with the app's own trace, and
that it can never carry anything about a person.
"""

from __future__ import annotations

import time

from app.core.timing import StageTimer, current_timer, mark, trace_token


def test_the_token_is_the_first_eight_characters() -> None:
    # The Flutter client derives the same prefix from the same idempotency key,
    # so the app, this endpoint and the worker line up in a log search without
    # any of them sending the token to the others.
    assert trace_token("AB12CD34-EF56-7890-ABCD-EF1234567890") == "ab12cd34"


def test_the_token_strips_separators_like_the_client() -> None:
    assert trace_token("--ab-12-cd-34-ef--") == "ab12cd34"


def test_the_token_is_a_prefix_never_the_whole_key() -> None:
    key = "ab12cd34ef567890abcdef1234567890"
    token = trace_token(key)
    assert len(token) == 8
    assert token != key


def test_the_token_degrades_safely() -> None:
    assert trace_token(None) == "none"
    assert trace_token("") == "none"
    assert trace_token("---") == "none"


def test_marks_record_milliseconds_between_stages() -> None:
    timer = StageTimer(scope="tryon.submit", trace="ab12cd34")
    time.sleep(0.05)
    slow = timer.mark("freshen_urls")
    time.sleep(0.05)
    slower = timer.mark("moderate_person")

    # Each mark measures the gap since the PREVIOUS one, not since the start.
    assert slow >= 40
    assert slower >= 40
    assert timer.total_ms >= slow + slower


def test_the_line_carries_only_the_token_durations_and_counts() -> None:
    timer = StageTimer(scope="tryon.submit", trace="ab12cd34")
    timer.mark("freshen_urls")
    timer.mark("moderate_garments", 3)

    line = timer.render()

    assert line.startswith("tryon.submit trace=ab12cd34 total=")
    assert "moderate_garments=" in line
    assert "(3)" in line
    # Nothing that could identify a person or a resource.
    assert "http" not in line
    assert "@" not in line
    assert ".jpg" not in line
    assert "\n" not in line  # one copyable line


def test_the_ambient_timer_lets_a_helper_contribute_without_a_parameter() -> None:
    """The FASHN provider records its own stages this way.

    Passing a timer down through every signature between the worker and the
    provider would mean changing functions that have no other reason to know
    about timing.
    """
    timer = StageTimer(scope="tryon.worker", trace="ab12cd34")
    token = current_timer.set(timer)
    try:
        mark("provider_accept")
        mark("provider_inference", 12)
    finally:
        current_timer.reset(token)

    line = timer.render()
    assert "provider_accept=" in line
    assert "provider_inference=" in line
    assert "(12)" in line


def test_marking_outside_a_timed_operation_is_a_safe_no_op() -> None:
    # A helper can be called from an untimed path (a cron, a recovery re-run)
    # and must not care.
    current_timer.set(None)
    mark("provider_accept")  # must not raise


def test_instrumentation_does_no_io() -> None:
    """A timer must never make the thing it is measuring slower or different.

    Nothing in the module opens a socket, touches the database, or creates a
    job — the only side effect is one log line per operation.
    """
    import inspect

    from app.core import timing

    source = inspect.getsource(timing)
    for forbidden in ("httpx", "requests", "asyncpg", "get_pool", "enqueue"):
        assert forbidden not in source, f"timing must not reach for {forbidden}"
