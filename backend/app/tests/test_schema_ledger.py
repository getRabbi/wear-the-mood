"""A release must not be able to go out ahead of its schema.

Written directly against the 2026-08-21 incident: 1.0.23+28 shipped to Google
Play over a production database that had never run 0071, background removal was
broken for every user of that build, and nothing in the repository could have
noticed — `/readyz` proved the API could reach Postgres, which is a different
question from whether Postgres had the job type the code was about to insert.

So these tests are about the DIFFERENCE between those two questions.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

import app.routers.health_root as health
from app.core import schema_ledger as ledger
from app.main import app

client = TestClient(app)


# ── the manifest itself ──────────────────────────────────────────────────────


def test_every_required_migration_file_exists() -> None:
    """A required migration naming a file that is not in the repository would
    make the preflight fail forever, or (worse) be quietly skipped."""
    for req in ledger.REQUIRED:
        assert (ledger.MIGRATIONS_DIR / req.filename).is_file(), req.filename


def test_0071_is_required() -> None:
    """The one that caused the incident. If a later refactor drops it from this
    list, the protection is gone and this test is the thing that says so."""
    assert "0071" in {r.version for r in ledger.REQUIRED}


def test_every_required_probe_is_read_only() -> None:
    """These run on every readiness check against production."""
    for req in ledger.REQUIRED:
        lowered = " ".join(req.probe.split()).lower()
        assert lowered.startswith("select")
        for forbidden in ("insert ", "update ", "delete ", "drop ", "alter ", "create "):
            assert forbidden not in lowered, (req.version, forbidden)


def test_versions_are_unique() -> None:
    versions = [r.version for r in ledger.REQUIRED]
    assert len(versions) == len(set(versions))


def test_version_parsing_rejects_an_unnumbered_file() -> None:
    assert ledger.version_of("0071_cutout_temp_job.sql") == "0071"
    with pytest.raises(ValueError):
        ledger.version_of("cutout_temp_job.sql")


# ── checksums ────────────────────────────────────────────────────────────────


def test_checksum_ignores_line_endings(tmp_path: Path) -> None:
    """A Windows workstation and an Ubuntu runner must agree, or every migration
    looks drifted the moment it is checked from the other machine."""
    lf = tmp_path / "0001_a.sql"
    crlf = tmp_path / "0001_b.sql"
    lf.write_bytes(b"select 1;\nselect 2;\n")
    crlf.write_bytes(b"select 1;\r\nselect 2;\r\n")
    assert ledger.checksum_of(lf) == ledger.checksum_of(crlf)


def test_checksum_changes_when_the_sql_changes(tmp_path: Path) -> None:
    path = tmp_path / "0001_a.sql"
    path.write_bytes(b"select 1;\n")
    before = ledger.checksum_of(path)
    path.write_bytes(b"select 2;\n")
    assert ledger.checksum_of(path) != before


def test_required_checksums_cover_every_required_migration() -> None:
    assert set(ledger.required_checksums()) == {r.version for r in ledger.REQUIRED}


# ── the verdicts ─────────────────────────────────────────────────────────────


def _result(**kw: object) -> ledger.CapabilityResult:
    base = {
        "version": "0071",
        "filename": "0071_cutout_temp_job.sql",
        "breaks": "…",
        "present": True,
        "recorded": True,
    }
    return ledger.CapabilityResult(**{**base, **kw})  # type: ignore[arg-type]


def test_applied_and_recorded_is_ok() -> None:
    result = _result()
    assert result.ok
    assert result.status == "ok"


def test_a_missing_migration_blocks() -> None:
    """The build-28 state exactly: the code needs it, the database has not run
    it, and until now nothing said so."""
    result = _result(present=False, recorded=False)
    assert not result.ok
    assert result.status == "missing"


def test_recorded_but_absent_is_the_dangerous_one() -> None:
    """The ledger claims it ran; the schema says otherwise. That is worse than
    an unrecorded migration, because it converts "we do not know" into a
    confident "yes" — so it must never read as ready."""
    result = _result(present=False, recorded=True)
    assert not result.ok
    assert result.status == "missing_recorded"


def test_checksum_drift_blocks_even_when_present() -> None:
    """The file was edited after it was applied, so the database ran SQL nobody
    can now read. Stop rather than guess which version is live."""
    result = _result(checksum_drift=True)
    assert not result.ok
    assert result.status == "checksum_drift"


def test_present_but_unrecorded_does_not_take_a_dyno_out_of_rotation() -> None:
    """Untidy bookkeeping is not an outage. The schema demonstrably has the
    change; only the ledger row is missing, and `baseline --probe` adopts it."""
    result = _result(recorded=False)
    assert result.ok
    assert result.status == "present_unrecorded"


# ── the readiness payload ────────────────────────────────────────────────────


def test_summary_is_ready_when_everything_is_present() -> None:
    summary = ledger.schema_summary([_result(), _result(version="0070")])
    assert summary["ready"] is True
    assert summary["blocked_by"] == []


def test_summary_names_what_is_blocking_and_why() -> None:
    summary = ledger.schema_summary(
        [_result(), _result(version="0071", present=False, recorded=False, breaks="bg removal")]
    )
    assert summary["ready"] is False
    blocked = summary["blocked_by"]
    assert [b["version"] for b in blocked] == ["0071"]
    # An operator reading this at 2am needs the consequence, not just a number.
    assert blocked[0]["breaks"] == "bg removal"


def test_summary_reports_unrecorded_without_blocking() -> None:
    summary = ledger.schema_summary([_result(recorded=False)])
    assert summary["ready"] is True
    assert summary["unrecorded"] == ["0071"]


# ── /readyz ──────────────────────────────────────────────────────────────────


class _Conn:
    """A database that either has every required change, or none of them.

    Deliberately does NOT special-case the ledger-existence lookup: that query
    and 0078's own probe are the same question, so answering them differently
    would be the fake inventing a state Postgres cannot be in.
    """

    def __init__(self, present: bool) -> None:
        self.present = present

    async def fetchval(self, sql: str, *args: object) -> object:
        return self.present

    async def fetch(self, sql: str, *args: object) -> list:
        return []  # ledger present but empty — the pre-baseline state


class _Acquire:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    async def __aenter__(self) -> _Conn:
        return self.conn

    async def __aexit__(self, *a: object) -> bool:
        return False


class _Pool:
    def __init__(self, conn: _Conn) -> None:
        self.conn = conn

    def acquire(self) -> _Acquire:
        return _Acquire(self.conn)


def _wire(monkeypatch: pytest.MonkeyPatch, *, db_ok: bool, present: bool) -> None:
    async def _ping() -> bool:
        return db_ok

    monkeypatch.setattr(health, "ping", _ping)
    monkeypatch.setattr(health, "get_pool", lambda: _Pool(_Conn(present)))


def test_readyz_is_503_when_a_required_migration_is_missing(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """THE regression test for the incident. The process is alive and the
    database is reachable — the two things `/readyz` used to check — and it must
    still refuse to call itself ready."""
    _wire(monkeypatch, db_ok=True, present=False)
    resp = client.get("/readyz")
    assert resp.status_code == 503
    body = resp.json()
    assert body["db"] is True
    assert body["status"] == "not_ready"
    assert body["schema"]["ready"] is False
    assert "0071" in {b["version"] for b in body["schema"]["blocked_by"]}


def test_readyz_is_200_when_the_schema_can_serve_the_build(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    _wire(monkeypatch, db_ok=True, present=True)
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json()["schema"]["ready"] is True


def test_readyz_does_not_fail_closed_when_the_probe_itself_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A broken probe is our bug, not the database's. Taking every dyno out of
    rotation over it would turn a monitoring defect into an outage — so it
    degrades to "unknown" and leaves the verdict to the DB ping."""

    async def _ping() -> bool:
        return True

    def _boom() -> object:
        raise RuntimeError("pool exploded")

    monkeypatch.setattr(health, "ping", _ping)
    monkeypatch.setattr(health, "get_pool", _boom)
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json()["schema"]["ready"] is None
    assert resp.json()["schema"]["error"] == "RuntimeError"
