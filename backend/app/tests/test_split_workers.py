"""Split workers + recovery: exact-job claim, duplicate/terminal no-op, poison,
rembg→enrichment handoff, kind routing, and stale recovery (blueprint §11.4, §11.6, §11.15)."""

from __future__ import annotations

import asyncio

import app.tasks.recovery as recovery
import app.workers.ai_orchestrator as orch
import app.workers.rembg_worker as rembg
from app.queues.message import KIND_AI, KIND_ENRICHMENT, KIND_REMBG, KIND_TRYON, QueueMessage
from app.queues.stub import StubQueue


class _Conn:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple]] = []
        self.fetch_results: dict[str, list] = {}

    async def execute(self, sql: str, *args: object) -> str:
        self.executed.append((sql, args))
        return "UPDATE 1"

    async def fetch(self, sql: str, *args: object) -> list:
        for key, rows in self.fetch_results.items():
            if key in sql:
                return rows
        return []

    async def fetchrow(self, sql: str, *args: object):
        return None

    async def fetchval(self, sql: str, *args: object):
        return None


def _row(**kw):
    kw.setdefault("attempt_count", 1)
    return kw


# ── rembg worker ────────────────────────────────────────────────────────────


def test_rembg_exact_claim_deletes_signal_and_hands_off(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("jobs", QueueMessage.new(KIND_REMBG, "J1"))
        claimed: list[str] = []
        processed: list[str] = []
        handoff: list[tuple[str, str]] = []

        async def fake_claim(conn, job_id, *, stale_seconds):
            claimed.append(str(job_id))
            return _row(id="J1", user_id="U", image_url="x", title=None, category=None)

        async def fake_cutout(conn, item):
            processed.append(item["id"])
            return b"cut"

        async def fake_enqueue(kind, job_id, *, provider=None, trace_id=None):
            handoff.append((kind, str(job_id)))
            return True

        monkeypatch.setattr(rembg, "claim_cutout", fake_claim)
        monkeypatch.setattr(rembg, "process_cutout", fake_cutout)
        monkeypatch.setattr(rembg, "enqueue_signal", fake_enqueue)

        n = await rembg.run_once(_Conn(), q, stale_seconds=300, max_attempts=5)
        assert n == 1
        assert claimed == ["J1"]  # claimed the referenced job
        assert processed == ["J1"]
        assert handoff == [(KIND_ENRICHMENT, "J1")]  # one enrichment handoff
        assert q.depth("jobs") == 0  # signal deleted after claim

    asyncio.run(run())


def test_rembg_duplicate_or_terminal_is_noop(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("jobs", QueueMessage.new(KIND_REMBG, "gone"))
        processed: list[str] = []

        async def fake_claim(conn, job_id, *, stale_seconds):
            return None  # already done / missing / held by another replica

        async def fake_cutout(conn, item):
            processed.append(item["id"])
            return b"cut"

        monkeypatch.setattr(rembg, "claim_cutout", fake_claim)
        monkeypatch.setattr(rembg, "process_cutout", fake_cutout)

        await rembg.run_once(_Conn(), q, stale_seconds=300, max_attempts=5)
        assert processed == []  # nothing processed
        assert q.depth("jobs") == 0  # duplicate/stale signal still deleted

    asyncio.run(run())


def test_rembg_poison_marks_failed_without_processing(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("jobs", QueueMessage.new(KIND_REMBG, "P"))
        processed: list[str] = []

        async def fake_claim(conn, job_id, *, stale_seconds):
            return _row(id="P", attempt_count=6)  # exceeds max_attempts=5

        async def fake_cutout(conn, item):
            processed.append(item["id"])
            return b"cut"

        monkeypatch.setattr(rembg, "claim_cutout", fake_claim)
        monkeypatch.setattr(rembg, "process_cutout", fake_cutout)

        conn = _Conn()
        await rembg.run_once(conn, q, stale_seconds=300, max_attempts=5)
        assert processed == []
        assert any("cutout_status = 'failed'" in sql for sql, _ in conn.executed)

    asyncio.run(run())


def test_rembg_foreign_kind_dropped(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("jobs", QueueMessage.new(KIND_TRYON, "wrong"))
        called: list[str] = []

        async def fake_claim(conn, job_id, *, stale_seconds):
            called.append(str(job_id))
            return None

        monkeypatch.setattr(rembg, "claim_cutout", fake_claim)
        await rembg.run_once(_Conn(), q, stale_seconds=300, max_attempts=5)
        assert called == []  # never tried to claim a non-rembg message
        assert q.depth("jobs") == 0

    asyncio.run(run())


# ── orchestrator ────────────────────────────────────────────────────────────


def test_orchestrator_routes_by_kind(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("enrichment", QueueMessage.new(KIND_TRYON, "T"))
        await q.send_signal("enrichment", QueueMessage.new(KIND_AI, "A"))
        await q.send_signal("enrichment", QueueMessage.new(KIND_ENRICHMENT, "E"))
        did: list[str] = []

        async def claim_tryon(conn, job_id, *, stale_seconds):
            return _row(id="T", user_id="U")

        async def claim_ai(conn, job_id, *, stale_seconds):
            return _row(id="A", user_id="U", job_type="enhance_item")

        async def do_tryon(conn, row):
            did.append("tryon:" + row["id"])

        async def do_ai(conn, row):
            did.append("ai:" + row["id"])

        async def do_enrich(conn, item_id):
            did.append("enrich:" + str(item_id))

        monkeypatch.setattr(orch, "claim_tryon_job", claim_tryon)
        monkeypatch.setattr(orch, "claim_ai_job", claim_ai)
        monkeypatch.setattr(orch.tryon_worker, "process_job", do_tryon)
        monkeypatch.setattr(orch.ai_jobs_worker, "process_ai_job", do_ai)
        monkeypatch.setattr(orch, "_enrich", do_enrich)

        await orch.run_once(_Conn(), q, stale_seconds=300, max_attempts=5)
        assert sorted(did) == ["ai:A", "enrich:E", "tryon:T"]
        assert q.depth("enrichment") == 0

    asyncio.run(run())


def test_orchestrator_tryon_poison_refunds_without_processing(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        await q.send_signal("enrichment", QueueMessage.new(KIND_TRYON, "T"))
        refunded: list[str] = []
        processed: list[str] = []

        async def claim_tryon(conn, job_id, *, stale_seconds):
            return _row(id="T", user_id="U", attempt_count=9)

        async def fail_refund(conn, *, job_id, user_id, error, provider, latency_ms, images):
            refunded.append(str(job_id))

        async def do_tryon(conn, row):
            processed.append(row["id"])

        monkeypatch.setattr(orch, "claim_tryon_job", claim_tryon)
        monkeypatch.setattr(orch.tryon_worker, "_fail_and_refund", fail_refund)
        monkeypatch.setattr(orch.tryon_worker, "process_job", do_tryon)

        await orch.run_once(_Conn(), q, stale_seconds=300, max_attempts=5)
        assert refunded == ["T"]
        assert processed == []

    asyncio.run(run())


# ── recovery ────────────────────────────────────────────────────────────────


def test_recovery_resignals_and_poisons(monkeypatch) -> None:
    async def run() -> None:
        q = StubQueue()
        conn = _Conn()
        conn.fetch_results = {
            "tryon_jobs": [
                _row(id="t-live", user_id="U", attempt_count=1),  # re-signal
                _row(id="t-dead", user_id="U", attempt_count=5),  # poison (>= max)
            ],
            "ai_jobs": [],
            "wardrobe_items": [_row(id="w-live", attempt_count=0)],  # re-signal cutout
        }
        poisoned: list[str] = []

        async def fail_refund(conn, *, job_id, user_id, error, provider, latency_ms, images):
            poisoned.append(str(job_id))

        monkeypatch.setattr(recovery.tryon_worker, "_fail_and_refund", fail_refund)

        counts = await recovery._recover(conn, q, stale=300, max_attempts=5)
        assert counts["tryon_resignal"] == 1
        assert counts["tryon_poison"] == 1
        assert counts["cutout_resignal"] == 1
        assert poisoned == ["t-dead"]
        # two duplicate-safe wake signals emitted (one tryon, one rembg)
        assert q.depth("enrichment") == 1
        assert q.depth("jobs") == 1

    asyncio.run(run())


def test_recovery_no_db_is_noop() -> None:
    # _run() with no CONNECTION_STRING returns 0 (recovery is a safe no-op).
    from app.core.config import get_settings

    if get_settings().connection_string:
        return  # a real DSN is configured; skip the no-op path
    assert recovery.main() == 0
