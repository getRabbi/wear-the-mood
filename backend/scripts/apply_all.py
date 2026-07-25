"""Apply the baseline + every ordered migration to the database, in order.

Ops/dev tool only — NOT shipped in any client. Idempotent (safe to re-run). Uses
the DIRECT 5432 connection (CONNECTION_STRING_DIRECT) for DDL/admin, falling back
to the runtime 6543 pooler (CONNECTION_STRING) with a warning (Phase 2B). Reads
from a git-ignored env file (default backend/.env; pass another, e.g. .env.prod,
to target prod without clobbering your dev .env).

Usage (run from backend/):
    python scripts/apply_all.py              # uses backend/.env
    python scripts/apply_all.py .env.prod    # uses backend/.env.prod
"""

from __future__ import annotations

import sys
from pathlib import Path

# Make the backend package importable when run as `python scripts/apply_all.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg  # noqa: E402  (after sys.path setup)
from dotenv import dotenv_values  # noqa: E402

from app.core.config import pick_migration_dsn  # noqa: E402


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent.parent
    supabase = repo_root / "supabase"
    files = [supabase / "FASHIONOS_BASELINE.sql"]
    files += sorted((supabase / "migrations").glob("*.sql"))  # 0001…0009, in order

    missing = [f for f in files if not f.exists()]
    if missing:
        print("missing files:", ", ".join(str(m) for m in missing))
        return 1

    env_name = sys.argv[1] if len(sys.argv) > 1 else ".env"
    env_path = Path(__file__).resolve().parent.parent / env_name
    if not env_path.exists():
        print(f"env file not found: backend/{env_name}")
        return 1
    dsn, used_fallback = pick_migration_dsn(dotenv_values(env_path))
    if not dsn:
        print(f"Neither CONNECTION_STRING_DIRECT nor CONNECTION_STRING set in backend/{env_name}")
        return 1
    if used_fallback:
        print(
            f"WARNING: CONNECTION_STRING_DIRECT not set in backend/{env_name} — using "
            "CONNECTION_STRING (6543 pooler). Prefer the direct 5432 string for DDL/admin."
        )
    else:
        print(f"Using CONNECTION_STRING_DIRECT (direct 5432) from backend/{env_name}")

    print(f"Applying {len(files)} SQL files to the target database…")
    with psycopg.connect(dsn, autocommit=True, prepare_threshold=None) as conn:
        for sql_file in files:
            print(f"  -> {sql_file.name}")
            with conn.cursor() as cur:
                cur.execute(sql_file.read_text(encoding="utf-8"))
        with conn.cursor() as cur:
            cur.execute("select count(*) from pg_tables where schemaname = 'public'")
            tables = cur.fetchone()[0]
            cur.execute(
                "select count(*) from pg_tables where schemaname = 'public' and rowsecurity = true"
            )
            rls = cur.fetchone()[0]
    print(f"OK. public tables: {tables} | RLS-enabled: {rls}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
