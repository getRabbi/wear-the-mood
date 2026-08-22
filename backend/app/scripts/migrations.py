"""Migration ledger runner — status, baseline, apply, preflight.

    python -m app.scripts.migrations status
    python -m app.scripts.migrations baseline --probe [--apply]
    python -m app.scripts.migrations apply 0071_cutout_temp_job.sql [--apply]
    python -m app.scripts.migrations preflight

Reads its DSN from `MIGRATION_DSN` (falling back to `CONNECTION_STRING_DIRECT`
then `CONNECTION_STRING`), which is the same value the running API uses — so
"the migration went to the database the API actually reads" is true by
construction rather than by trust. The DSN is never printed.

DESIGN RULES, each one earned by the build-28 incident:

  * **Nothing is destructive by default.** Every subcommand that could write
    requires an explicit `--apply`; without it you get a report.
  * **A row is never written for a change that has not taken effect.** `baseline`
    records a version only when its probe says the schema really has it. There
    is deliberately no "trust me, mark it applied" switch.
  * **Ambiguity stops the run.** A recorded migration whose probe says the
    schema does NOT have it, or whose checksum no longer matches the file, is
    reported and exits non-zero. That combination means the ledger and the
    database disagree, and guessing which one is right is how you get an outage
    with a green dashboard.
  * **History is not replayed.** `apply` runs only the files you name.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from app.core.schema_ledger import (
    MIGRATIONS_DIR,
    REQUIRED,
    CapabilityResult,
    all_migrations,
    checksum_of,
    version_of,
)

try:  # psycopg is a runner dependency, not an API one.
    import psycopg
except ImportError:  # pragma: no cover - exercised only outside CI
    psycopg = None  # type: ignore[assignment]


LEDGER_EXISTS = """
select exists (
  select 1 from information_schema.tables
   where table_schema = 'public' and table_name = 'schema_migrations'
)
"""

LEDGER_ROWS = "select version, filename, checksum, source, applied_at from public.schema_migrations"

RECORD = """
insert into public.schema_migrations (version, filename, checksum, source, applied_by)
values (%s, %s, %s, %s, %s)
on conflict (version) do update
   set filename = excluded.filename,
       checksum = excluded.checksum,
       applied_at = now(),
       source = excluded.source,
       applied_by = excluded.applied_by
"""


def _dsn() -> str:
    for key in ("MIGRATION_DSN", "CONNECTION_STRING_DIRECT", "CONNECTION_STRING"):
        value = os.environ.get(key)
        if value:
            return value
    sys.exit("no DSN: set MIGRATION_DSN (or CONNECTION_STRING_DIRECT/CONNECTION_STRING)")


def _actor() -> str:
    return os.environ.get("GITHUB_ACTOR") or os.environ.get("USER") or "unknown"


def _connect():
    if psycopg is None:
        sys.exit("psycopg is not installed: pip install 'psycopg[binary]'")
    return psycopg.connect(_dsn(), connect_timeout=30)


def _ledger(cur) -> dict[str, dict]:
    """version → recorded row, or {} when the ledger table does not exist yet."""
    if not cur.execute(LEDGER_EXISTS).fetchone()[0]:
        return {}
    return {
        row[0]: {"filename": row[1], "checksum": row[2], "source": row[3], "applied_at": row[4]}
        for row in cur.execute(LEDGER_ROWS).fetchall()
    }


def _evaluate(cur) -> list[CapabilityResult]:
    """Ask the SCHEMA about every required migration, then compare to the ledger."""
    recorded = _ledger(cur)
    results: list[CapabilityResult] = []
    for req in REQUIRED:
        present = bool(cur.execute(req.probe).fetchone()[0])
        row = recorded.get(req.version)
        drift = False
        if row is not None:
            drift = row["checksum"] != checksum_of(MIGRATIONS_DIR / req.filename)
        results.append(
            CapabilityResult(
                version=req.version,
                filename=req.filename,
                breaks=req.breaks,
                present=present,
                recorded=row is not None,
                checksum_drift=drift,
            )
        )
    return results


_SYMBOL = {
    "ok": "  ok  ",
    "present_unrecorded": " note ",
    "missing": " FAIL ",
    "missing_recorded": " FAIL ",
    "checksum_drift": " FAIL ",
}


def _report(results: list[CapabilityResult]) -> None:
    print(f"{'':6} {'ver':<6}{'status':<20}migration")
    for r in results:
        print(f"[{_SYMBOL[r.status]}] {r.version:<6}{r.status:<20}{r.filename}")
        if r.status == "missing":
            print(f"         -> NOT APPLIED. {r.breaks}")
        elif r.status == "missing_recorded":
            print(
                "         -> THE LEDGER AND THE DATABASE DISAGREE: recorded as "
                "applied, but the schema does not have it. Do not deploy; "
                f"investigate by hand. {r.breaks}"
            )
        elif r.status == "checksum_drift":
            print(
                "         -> the file changed AFTER it was applied. The database "
                "ran a different version of this SQL than the one on disk."
            )
        elif r.status == "present_unrecorded":
            print("         -> present in the schema but not in the ledger; `baseline --probe`.")


# ── subcommands ──────────────────────────────────────────────────────────────


def cmd_status(_args: argparse.Namespace) -> int:
    with _connect() as conn, conn.cursor() as cur:
        results = _evaluate(cur)
        recorded = _ledger(cur)
    _report(results)

    known = {version_of(p.name) for p in all_migrations()}
    unrecorded = sorted(known - set(recorded))
    print(
        f"\n{len(all_migrations())} migration file(s) on disk, "
        f"{len(recorded)} recorded, {len(unrecorded)} unrecorded."
    )
    if unrecorded:
        # Informational ONLY. Most of these predate the ledger and were applied
        # long ago; the list is not a to-do, and running them would be exactly
        # the blind replay this tool refuses to do.
        print("unrecorded (not necessarily unapplied): " + ", ".join(unrecorded[:20]))
    return 0 if all(r.ok for r in results) else 1


def cmd_preflight(_args: argparse.Namespace) -> int:
    """The gate a release runs. Non-zero means: do not promote this build."""
    with _connect() as conn, conn.cursor() as cur:
        results = _evaluate(cur)
    _report(results)
    blocking = [r for r in results if not r.ok]
    if blocking:
        print(
            "\nRELEASE BLOCKED — "
            + ", ".join(f"{r.version} ({r.status})" for r in blocking)
            + "\nApply the migration FIRST, then deploy the backend, then the client."
        )
        return 1
    print("\nPreflight OK — every required migration is present in this database.")
    return 0


def cmd_baseline(args: argparse.Namespace) -> int:
    """Adopt an EXISTING database into the ledger, on evidence alone.

    Only versions whose probe says the schema really has the change are
    recorded, and they are marked `baselined` so nobody later mistakes an
    inference for a receipt. A required migration that is genuinely missing is
    reported and left unrecorded — marking it applied would hard-code the exact
    lie that caused the incident.
    """
    with _connect() as conn, conn.cursor() as cur:
        results = _evaluate(cur)
        _report(results)

        adoptable = [r for r in results if r.present and not r.recorded]
        missing = [r for r in results if not r.present]
        drifted = [r for r in results if r.checksum_drift]

        if drifted:
            print("\nRefusing to baseline: checksum drift above must be resolved by hand.")
            return 1
        if not adoptable:
            print("\nNothing to baseline.")
            return 1 if missing else 0

        print("\nWould record as `baselined` (schema evidence confirmed):")
        for r in adoptable:
            print(f"  {r.version}  {r.filename}")
        if missing:
            print("\nDeliberately NOT recorded (the schema does not have them):")
            for r in missing:
                print(f"  {r.version}  {r.filename}")

        if not args.apply:
            print("\nDry run. Re-run with --apply to write these rows.")
            return 0

        for r in adoptable:
            cur.execute(
                RECORD,
                (
                    r.version,
                    r.filename,
                    checksum_of(MIGRATIONS_DIR / r.filename),
                    "baselined",
                    _actor(),
                ),
            )
        conn.commit()
        print(f"\nRecorded {len(adoptable)} baselined migration(s).")
        return 1 if missing else 0


def cmd_apply(args: argparse.Namespace) -> int:
    """Apply the named migrations, in order, and record each one."""
    paths: list[Path] = []
    for name in args.files:
        path = MIGRATIONS_DIR / name
        if not path.exists():
            sys.exit(f"missing migration: {path}")
        paths.append(path)

    with _connect() as conn, conn.cursor() as cur:
        recorded = _ledger(cur)
        for path in paths:
            version = version_of(path.name)
            row = recorded.get(version)
            if row and row["checksum"] != checksum_of(path):
                sys.exit(
                    f"{path.name}: already applied, but the file has changed since. "
                    "The database ran different SQL than what is on disk — resolve "
                    "by hand rather than re-running."
                )

        print(f"{'APPLYING' if args.apply else 'DRY RUN'}: {len(paths)} file(s)")
        for path in paths:
            already = version_of(path.name) in recorded
            note = "  [already recorded — re-running is safe, they are idempotent]"
            print(f"  - {path.name} ({path.stat().st_size} bytes){note if already else ''}")
        if not args.apply:
            return 0

        for path in paths:
            print(f"\n=== {path.name}")
            # One transaction per file. Each migration is individually
            # idempotent, so a failure part-way through a set leaves the earlier
            # files applied and re-runnable rather than rolling back work that
            # succeeded. The ledger row is written INSIDE the same transaction,
            # so "the SQL ran" and "we recorded that it ran" can never disagree.
            with conn.transaction():
                cur.execute(path.read_text(encoding="utf-8"))
                # Record only once the ledger exists. 0078 CREATES it, so inside
                # its own transaction the table appears part-way through and it
                # records itself — rather than being the one migration nothing
                # can ever account for. Anything applied before 0078 runs is
                # left unrecorded and picked up later by `baseline --probe`,
                # which is honest: we know it ran, we just had nowhere to say so.
                recorded_now = _ledger_now(cur)
                if recorded_now:
                    cur.execute(
                        RECORD,
                        (
                            version_of(path.name),
                            path.name,
                            checksum_of(path),
                            "applied",
                            _actor(),
                        ),
                    )
            print(
                "    applied + recorded" if recorded_now else "    applied (ledger not created yet)"
            )
    print("\nall migrations applied")
    return 0


def _ledger_now(cur) -> bool:
    """Whether the ledger table exists RIGHT NOW.

    0078 creates the ledger, so within its own transaction the table appears
    part-way through; this is what lets it record itself rather than being the
    one migration nothing can ever account for.
    """
    return bool(cur.execute(LEDGER_EXISTS).fetchone()[0])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="report every required migration").set_defaults(fn=cmd_status)
    sub.add_parser("preflight", help="gate a release on schema readiness").set_defaults(
        fn=cmd_preflight
    )

    baseline = sub.add_parser("baseline", help="adopt an existing database, on evidence")
    baseline.add_argument(
        "--probe", action="store_true", help="accepted for readability; always on"
    )
    baseline.add_argument("--apply", action="store_true", help="write the rows (default: report)")
    baseline.set_defaults(fn=cmd_baseline)

    apply_cmd = sub.add_parser("apply", help="apply named migrations, in order")
    apply_cmd.add_argument("files", nargs="+")
    apply_cmd.add_argument("--apply", action="store_true", help="execute (default: report)")
    apply_cmd.set_defaults(fn=cmd_apply)

    args = parser.parse_args(argv)
    return int(args.fn(args))


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
