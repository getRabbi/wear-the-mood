"""Which migrations this build REQUIRES, and how to prove they are really there.

The 0071 incident in one sentence: the API was released to production against a
database that had never run the migration it depended on, and every layer that
could have noticed was answering a different question. `/readyz` proved the
process could reach Postgres. `migration-deploy` proved an image had been built.
Nobody proved the schema had the thing the code was about to use.

So this module is deliberately built around EVIDENCE rather than bookkeeping.
Every required migration carries a `probe` — a read-only query that asks the
schema directly whether the change took effect ("does `ai_jobs.job_type` accept
`cutout_temp`?"), not whether a row somewhere claims it did. That ordering
matters in both directions:

  * a ledger row with no matching schema is a LIE, and the preflight says so;
  * a schema change with no ledger row is merely UNRECORDED, and `baseline
    --probe` can safely adopt it, because the probe is what supplies the proof.

`REQUIRED` is not "every migration ever written" — replaying 78 files against a
live database is exactly the blind action this is here to prevent. It is the
short list the CURRENTLY RUNNING CODE cannot work without, so a release blocked
by it is a release that would genuinely have been broken.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path

#: Repository root, from `backend/app/core/` → three parents up.
REPO_ROOT = Path(__file__).resolve().parents[3]
MIGRATIONS_DIR = REPO_ROOT / "supabase" / "migrations"

_VERSION_RE = re.compile(r"^(\d{4})_")


@dataclass(frozen=True)
class RequiredMigration:
    """A migration the running backend depends on, and how to verify it."""

    version: str
    filename: str
    #: What breaks in the product when this is missing. Printed by the preflight,
    #: because "0071 is pending" tells an operator nothing at 2am.
    breaks: str
    #: A read-only SQL query returning a single boolean: is the change PRESENT?
    #: Never a write, never a DDL, safe to run against production on every boot.
    probe: str


#: sha256 over LF-normalised bytes. Windows workstations and Ubuntu runners have
#: to agree, and `.gitattributes` normalising to LF in the repo is not the same
#: as guaranteeing what lands in a working tree.
def checksum_of(path: Path) -> str:
    raw = path.read_bytes().replace(b"\r\n", b"\n")
    return hashlib.sha256(raw).hexdigest()


def version_of(filename: str) -> str:
    match = _VERSION_RE.match(filename)
    if not match:
        raise ValueError(f"migration filename has no NNNN_ prefix: {filename}")
    return match.group(1)


def all_migrations() -> list[Path]:
    """Every ordered migration file, ascending. The repository's own history."""
    return sorted(p for p in MIGRATIONS_DIR.glob("*.sql") if _VERSION_RE.match(p.name))


# ── the short list a release actually depends on ─────────────────────────────
#
# Adding to this list is how you make a deploy refuse to go out ahead of its
# schema. Keep it to changes whose absence breaks a user-visible path — that is
# what keeps the signal worth stopping for.

REQUIRED: tuple[RequiredMigration, ...] = (
    RequiredMigration(
        version="0069",
        filename="0069_tryon_execution_plan.sql",
        breaks=(
            "Every wardrobe write fails: the API stores a canonical role on each "
            "item and the column would not exist."
        ),
        probe="""
            select exists (
              select 1 from information_schema.columns
               where table_schema = 'public'
                 and table_name = 'wardrobe_items'
                 and column_name = 'canonical_category'
            )
        """,
    ),
    RequiredMigration(
        version="0070",
        filename="0070_tryon_category_gate.sql",
        breaks=(
            "Catalog try-on eligibility cannot be evaluated: "
            "product_tryon_ready() calls tryon_capable_category()."
        ),
        probe="""
            select exists (
              select 1 from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname = 'tryon_capable_category'
            )
        """,
    ),
    RequiredMigration(
        version="0071",
        filename="0071_cutout_temp_job.sql",
        breaks=(
            "THE BUILD-28 INCIDENT. Add Garment removes the background before it "
            "asks what the piece is, which needs a cutout_temp job to hold the "
            "result. Without it every background removal fails at the last step."
        ),
        # Both halves, because either one alone is a half-applied 0071: the
        # constraint is what lets the job row exist, `adopted_at` is what stops
        # the reaper deleting a garment's cutout out from under it.
        probe="""
            select
              exists (
                select 1 from pg_constraint con
                join pg_class rel on rel.oid = con.conrelid
                join pg_namespace nsp on nsp.oid = rel.relnamespace
                 where nsp.nspname = 'public'
                   and rel.relname = 'ai_jobs'
                   and con.contype = 'c'
                   and pg_get_constraintdef(con.oid) like '%cutout_temp%'
              )
              and exists (
                select 1 from information_schema.columns
                 where table_schema = 'public'
                   and table_name = 'ai_jobs'
                   and column_name = 'adopted_at'
              )
        """,
    ),
    RequiredMigration(
        version="0078",
        filename="0078_migration_ledger.sql",
        breaks="The ledger itself is missing, so nothing above can be recorded.",
        probe="""
            select exists (
              select 1 from information_schema.tables
               where table_schema = 'public' and table_name = 'schema_migrations'
            )
        """,
    ),
)


def required_by_version() -> dict[str, RequiredMigration]:
    return {r.version: r for r in REQUIRED}


def required_checksums() -> dict[str, str]:
    """version → checksum of the file on disk, for every required migration."""
    return {r.version: checksum_of(MIGRATIONS_DIR / r.filename) for r in REQUIRED}


@dataclass(frozen=True)
class CapabilityResult:
    """One required migration, as the DATABASE currently answers for it."""

    version: str
    filename: str
    breaks: str
    #: The probe's verdict: is the schema change actually present?
    present: bool
    #: Whether the ledger has a row for it.
    recorded: bool
    #: Set when the ledger's checksum disagrees with the file on disk.
    checksum_drift: bool = False

    @property
    def ok(self) -> bool:
        """Ready to serve. PRESENT is what matters — a recorded-but-absent row is
        the dangerous case and is never ok; an unrecorded-but-present schema is
        merely untidy and does not break a user."""
        return self.present and not self.checksum_drift

    @property
    def status(self) -> str:
        if self.checksum_drift:
            return "checksum_drift"
        if not self.present:
            return "missing_recorded" if self.recorded else "missing"
        return "ok" if self.recorded else "present_unrecorded"


# ── the same question, asked by the running API ──────────────────────────────


async def evaluate_capabilities(conn: object) -> list[CapabilityResult]:
    """Probe every required migration over an asyncpg connection.

    Shares its list, its probes and its verdicts with `scripts/migrations.py`,
    so the answer a release preflight gets and the answer a running dyno reports
    cannot disagree — one of them being right while the other was silent is the
    shape of the last incident.

    Read-only and cheap: four `exists(...)` catalogue lookups. Nothing here can
    write, so it is safe on every readiness check.
    """
    ledger_exists = await conn.fetchval(
        """
        select exists (
          select 1 from information_schema.tables
           where table_schema = 'public' and table_name = 'schema_migrations'
        )
        """
    )
    recorded: dict[str, str] = {}
    if ledger_exists:
        rows = await conn.fetch("select version, checksum from public.schema_migrations")
        recorded = {r["version"]: r["checksum"] for r in rows}

    results: list[CapabilityResult] = []
    for req in REQUIRED:
        present = bool(await conn.fetchval(req.probe))
        stored = recorded.get(req.version)
        results.append(
            CapabilityResult(
                version=req.version,
                filename=req.filename,
                breaks=req.breaks,
                present=present,
                recorded=stored is not None,
                checksum_drift=(
                    stored is not None and stored != checksum_of(MIGRATIONS_DIR / req.filename)
                ),
            )
        )
    return results


def schema_summary(results: list[CapabilityResult]) -> dict[str, object]:
    """Non-secret readiness payload: is the schema able to serve this build?

    `ready` is driven by the PROBES, not by the ledger. A missing ledger row on a
    database that demonstrably has the change is untidy bookkeeping and must not
    take a healthy dyno out of rotation; a missing CHANGE is a real outage and
    must be visible immediately — which on 2026-08-21 it was not.
    """
    blocking = [r for r in results if not r.ok]
    return {
        "ready": not blocking,
        "required": len(results),
        "blocked_by": [
            {"version": r.version, "status": r.status, "breaks": r.breaks} for r in blocking
        ],
        "unrecorded": [r.version for r in results if r.present and not r.recorded],
    }
