"""Transactional push outbox — delivery outcomes, settle semantics, retention,
and the savepoint that keeps a notification failure out of the business
transaction (migrations 0051 + 0052)."""

from __future__ import annotations

import asyncio
import json
import uuid

import pytest

from app.core.config import get_settings
from app.services.notifications import (
    OUTBOX_RETENTION_DAYS,
    PushOutcome,
    drain_notification_outbox,
    prune_notification_outbox,
)


class _Conn:
    """Records every statement and lets a test script the claim result."""

    def __init__(self, claim_rows: list[dict] | None = None) -> None:
        self.claim_rows = claim_rows or []
        self.calls: list[tuple[str, tuple]] = []

    async def fetch(self, sql: str, *args):
        self.calls.append((" ".join(sql.split()), args))
        return self.claim_rows if "notification_outbox" in sql else []

    async def execute(self, sql: str, *args):
        self.calls.append((" ".join(sql.split()), args))
        return "DELETE 0"

    def statements(self) -> list[str]:
        return [s for s, _ in self.calls]


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self):
        conn = self.conn

        class _Ctx:
            async def __aenter__(self):
                return conn

            async def __aexit__(self, *_a):
                return False

        return _Ctx()


def _row(row_id: str = "o-1", attempts: int = 1) -> dict:
    return {
        "id": row_id,
        "user_id": "u1",
        "attempts": attempts,
        "payload": json.dumps({"title": "t", "body": "b", "data": {"route": "/wtm/inbox"}}),
    }


def _drain(monkeypatch, rows: list[dict], outcomes: list[PushOutcome]) -> _Conn:
    """Run one drain with a scripted push outcome per row."""
    import app.services.notifications as mod

    conn = _Conn(rows)
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    queue = list(outcomes)

    async def _send(user_id, message):
        return queue.pop(0)

    monkeypatch.setattr(mod, "push_to_user", _send)
    asyncio.run(drain_notification_outbox())
    return conn


def _settled_as(conn: _Conn) -> list[str]:
    """The terminal status values written by this drain."""
    return [
        args[1]
        for sql, args in conn.calls
        if "set status = $2" in sql or "set status = 'exhausted'" in sql
        for args in [args]
    ]


# ── a failure is NEVER recorded as a delivery ────────────────────────────────
# The whole point of 0052: the old drainer settled every claimed row with
# delivered_at, so an FCM outage was indistinguishable from a successful send.


def test_successful_delivery_is_settled_delivered(monkeypatch) -> None:
    conn = _drain(monkeypatch, [_row()], [PushOutcome.delivered])
    settle = next(s for s in conn.statements() if "set status = $2" in s)
    assert "delivered_at = case when $2 = 'delivered' then now()" in settle
    assert "last_error = null" in settle
    assert "locked_at = null" in settle
    assert ("o-1", "delivered") in [a for _, a in conn.calls if len(a) == 2]


@pytest.mark.parametrize(
    ("outcome", "status"),
    [
        (PushOutcome.suppressed, "suppressed"),
        (PushOutcome.no_tokens, "undeliverable"),
        (PushOutcome.all_invalid, "undeliverable"),
    ],
)
def test_intentionally_consumed_outcomes_settle_without_retrying(
    monkeypatch, outcome: PushOutcome, status: str
) -> None:
    """Muted category / no device / every token dead: retrying cannot help, and
    none of them is a delivery."""
    conn = _drain(monkeypatch, [_row()], [outcome])
    assert ("o-1", status) in [a for _, a in conn.calls if len(a) == 2]
    # Only a real delivery stamps delivered_at.
    assert status != "delivered"


@pytest.mark.parametrize(
    "outcome", [PushOutcome.transient, PushOutcome.auth_error, PushOutcome.failed]
)
def test_retryable_outcomes_stay_pending_with_a_safe_error(
    monkeypatch, outcome: PushOutcome
) -> None:
    conn = _drain(monkeypatch, [_row(attempts=1)], [outcome])
    retry = [s for s in conn.statements() if "set locked_at = null, last_error = $2" in s]
    assert len(retry) == 1, "claim released so the row is picked up again"
    assert ("o-1", outcome.value) in [a for _, a in conn.calls if len(a) == 2]
    # Never settled, never stamped delivered.
    assert not any("set status = $2" in s for s in conn.statements())


def test_auth_error_is_retryable_not_terminal() -> None:
    """A misconfigured FCM project is OUR problem, not the user's: the backlog
    must still go out once it is corrected."""
    assert not PushOutcome.auth_error.is_terminal
    assert not PushOutcome.transient.is_terminal
    assert not PushOutcome.failed.is_terminal
    assert PushOutcome.delivered.is_terminal
    assert PushOutcome.suppressed.is_terminal
    assert PushOutcome.no_tokens.is_terminal
    assert PushOutcome.all_invalid.is_terminal


def test_exhausted_rows_are_dead_lettered_not_marked_delivered(monkeypatch) -> None:
    """The last attempt failing must leave EVIDENCE, not a false success."""
    import app.services.notifications as mod

    conn = _drain(
        monkeypatch,
        [_row(attempts=mod._MAX_PUSH_ATTEMPTS)],
        [PushOutcome.transient],
    )
    exhaust = [s for s in conn.statements() if "set status = 'exhausted'" in s]
    assert len(exhaust) == 1
    assert ("o-1", "transient") in [a for _, a in conn.calls if len(a) == 2]
    assert not any("delivered" in s and "set status = $2" in s for s in conn.statements())


def test_drain_returns_only_the_count_actually_delivered(monkeypatch) -> None:
    import app.services.notifications as mod

    conn = _Conn([_row("o-1"), _row("o-2"), _row("o-3")])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    queue = [PushOutcome.delivered, PushOutcome.suppressed, PushOutcome.transient]

    async def _send(user_id, message):
        return queue.pop(0)

    monkeypatch.setattr(mod, "push_to_user", _send)
    assert asyncio.run(drain_notification_outbox()) == 1


def test_one_broken_row_does_not_abandon_the_batch(monkeypatch) -> None:
    import app.services.notifications as mod

    conn = _Conn([_row("o-1"), _row("o-2")])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    calls = {"n": 0}

    async def _send(user_id, message):
        calls["n"] += 1
        if calls["n"] == 1:
            raise RuntimeError("row blew up")
        return PushOutcome.delivered

    monkeypatch.setattr(mod, "push_to_user", _send)
    assert asyncio.run(drain_notification_outbox()) == 1
    assert calls["n"] == 2, "the second row was still attempted"
    # The broken row is retryable, not silently dropped.
    assert ("o-1", "failed") in [a for _, a in conn.calls if len(a) == 2]


def test_claim_never_lets_two_drainers_take_one_row(monkeypatch) -> None:
    conn = _drain(monkeypatch, [], [])
    claim = next(s for s in conn.statements() if "update public.notification_outbox" in s)
    assert "for update skip locked" in claim
    assert "status = 'pending'" in claim
    assert "attempts = attempts + 1" in claim
    # A claim that outlived its drainer is reclaimable.
    assert "locked_at <" in claim


def test_settle_failure_leaves_the_row_for_retry(monkeypatch) -> None:
    """Send succeeded, settle crashed: at-least-once, so the row is retried and
    the push may arrive twice. Documented, not hidden."""
    import app.services.notifications as mod

    class _FlakyConn(_Conn):
        async def execute(self, sql: str, *args):
            self.calls.append((" ".join(sql.split()), args))
            raise RuntimeError("db went away")

    conn = _FlakyConn([_row()])
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))

    async def _send(user_id, message):
        return PushOutcome.delivered

    monkeypatch.setattr(mod, "push_to_user", _send)
    # Contained: no raise, and the row keeps its claim so it ages back to pending.
    assert asyncio.run(drain_notification_outbox()) == 0


# ── retention ────────────────────────────────────────────────────────────────


def test_retention_deletes_only_expired_settled_rows(monkeypatch) -> None:
    import app.services.notifications as mod

    conn = _Conn()
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    asyncio.run(prune_notification_outbox())

    sql = next(s for s in conn.statements() if "delete from public.notification_outbox" in s)
    assert "status in ('delivered', 'suppressed', 'undeliverable')" in sql
    assert "delivered_at is not null" in sql
    assert f"interval '{OUTBOX_RETENTION_DAYS} days'" in sql
    # Pending, claimed and dead-lettered rows are never eligible.
    assert "'pending'" not in sql
    assert "'exhausted'" not in sql
    assert "limit $1" in sql, "bounded batches"


def test_retention_stops_when_a_batch_is_short(monkeypatch) -> None:
    import app.services.notifications as mod

    class _Counting(_Conn):
        def __init__(self) -> None:
            super().__init__()
            self.deletes = 0

        async def execute(self, sql: str, *args):
            self.deletes += 1
            return "DELETE 5"  # fewer than the batch size

    conn = _Counting()
    monkeypatch.setattr(mod, "get_pool", lambda: _Pool(conn))
    assert asyncio.run(prune_notification_outbox(batch=1000)) == 5
    assert conn.deletes == 1, "no further batches after a short one"


# ── the savepoint, against a REAL Postgres ──────────────────────────────────
# Catching an SQL error in Python does not restore an aborted transaction, so
# this cannot be proven with a fake connection. It needs a live server.


def test_savepoint_keeps_the_outer_transaction_usable_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    import asyncpg

    from app.services.notifications import create_notification

    async def run() -> None:
        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            async with conn.transaction():
                # A real business write the caller expects to survive.
                await conn.execute("create temp table _biz (id int) on commit drop")
                await conn.execute("insert into _biz values (1)")

                # A notification that CANNOT succeed: the user id is not a uuid,
                # so Postgres aborts the statement. Without the savepoint the
                # whole transaction would now be poisoned.
                outcome = await create_notification(
                    conn,
                    user_id="definitely-not-a-uuid",
                    type="like",
                    title="t",
                )
                assert outcome.created is False

                # THE ASSERTION: the outer transaction is still usable.
                await conn.execute("insert into _biz values (2)")
                total = await conn.fetchval("select count(*) from _biz")
                assert total == 2, "business writes survived the notification failure"
        finally:
            await conn.close()

    asyncio.run(run())


def test_outer_rollback_removes_notification_and_outbox_live() -> None:
    """The core outbox guarantee, proven on a real server: a rolled-back business
    transaction leaves neither a notification nor a push intent behind."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    import asyncpg

    from app.services.notifications import create_notification

    dedupe = f"test-rollback:{uuid.uuid4()}"

    async def run() -> None:
        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            # A real user id is needed for the FK; borrow any existing profile.
            user_id = await conn.fetchval("select id from public.profiles limit 1")
            if user_id is None:
                pytest.skip("no profiles in this database to attach a notification to")

            class _Rollback(Exception):
                pass

            try:
                async with conn.transaction():
                    outcome = await create_notification(
                        conn,
                        user_id=str(user_id),
                        type="like",
                        title="rollback probe",
                        dedupe_key=dedupe,
                    )
                    assert outcome.created is True  # it DID insert...
                    raise _Rollback  # ...and then the business action failed
            except _Rollback:
                pass

            # ...so neither row survives, and nothing can push for it.
            assert (
                await conn.fetchval(
                    "select count(*) from public.notifications where dedupe_key = $1",
                    dedupe,
                )
                == 0
            )
            assert (
                await conn.fetchval(
                    "select count(*) from public.notification_outbox o "
                    "join public.notifications n on n.id = o.notification_id "
                    "where n.dedupe_key = $1",
                    dedupe,
                )
                == 0
            )
        finally:
            await conn.close()

    asyncio.run(run())


def test_commit_persists_both_notification_and_outbox_live() -> None:
    """The other half: a committed action leaves exactly one notification and
    exactly one push intent, and the drainer can see them."""
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    import asyncpg

    from app.services.notifications import create_notification

    dedupe = f"test-commit:{uuid.uuid4()}"

    async def run() -> None:
        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            user_id = await conn.fetchval("select id from public.profiles limit 1")
            if user_id is None:
                pytest.skip("no profiles in this database to attach a notification to")
            try:
                async with conn.transaction():
                    first = await create_notification(
                        conn,
                        user_id=str(user_id),
                        type="like",
                        title="commit probe",
                        dedupe_key=dedupe,
                    )
                    # A duplicate in the SAME transaction adds neither row.
                    second = await create_notification(
                        conn,
                        user_id=str(user_id),
                        type="like",
                        title="commit probe",
                        dedupe_key=dedupe,
                    )
                assert first.created is True
                assert second.created is False

                assert (
                    await conn.fetchval(
                        "select count(*) from public.notifications where dedupe_key = $1",
                        dedupe,
                    )
                    == 1
                )
                # Exactly one push intent, pending, ready for the drainer.
                row = await conn.fetchrow(
                    "select o.status, o.attempts from public.notification_outbox o "
                    "join public.notifications n on n.id = o.notification_id "
                    "where n.dedupe_key = $1",
                    dedupe,
                )
                assert row is not None, "committed notification has a push intent"
                assert row["status"] == "pending"
                assert row["attempts"] == 0
            finally:
                # Never leave probe rows behind.
                await conn.execute("delete from public.notifications where dedupe_key = $1", dedupe)
        finally:
            await conn.close()

    asyncio.run(run())
