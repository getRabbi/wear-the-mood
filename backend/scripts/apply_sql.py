"""Apply a .sql file to the migrations/admin database.

Ops/dev tool only — NOT shipped in any client. Uses the DIRECT 5432 connection
(CONNECTION_STRING_DIRECT) for DDL/admin, falling back to the runtime 6543 pooler
(CONNECTION_STRING) with a warning (Phase 2B). Reads from the git-ignored
backend/.env.

Usage (run from backend/):
    python scripts/apply_sql.py ../supabase/FASHIONOS_BASELINE.sql
"""

from __future__ import annotations

import sys
from pathlib import Path

# Make the backend package importable when run as `python scripts/apply_sql.py`.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg  # noqa: E402  (after sys.path setup)
from dotenv import dotenv_values  # noqa: E402

from app.core.config import pick_migration_dsn  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python scripts/apply_sql.py <path-to.sql>")
        return 2

    sql_path = Path(sys.argv[1])
    if not sql_path.exists():
        print(f"file not found: {sql_path}")
        return 1
    sql = sql_path.read_text(encoding="utf-8")

    env = dotenv_values(Path(__file__).resolve().parent.parent / ".env")
    dsn, used_fallback = pick_migration_dsn(env)
    if not dsn:
        print("Neither CONNECTION_STRING_DIRECT nor CONNECTION_STRING set in backend/.env")
        return 1
    if used_fallback:
        print(
            "WARNING: CONNECTION_STRING_DIRECT not set — using CONNECTION_STRING "
            "(6543 pooler) for migrations. Prefer the direct 5432 string for DDL/admin."
        )
    else:
        print("Using CONNECTION_STRING_DIRECT (direct 5432) for migrations.")

    print(f"Applying {sql_path.name} ...")
    with psycopg.connect(dsn, autocommit=True, prepare_threshold=None) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
        with conn.cursor() as cur:
            cur.execute(
                "select tablename from pg_tables where schemaname = 'public' order by tablename"
            )
            tables = [row[0] for row in cur.fetchall()]
            cur.execute(
                "select count(*) from pg_tables where schemaname = 'public' and rowsecurity = true"
            )
            rls_count = cur.fetchone()[0]

    print(f"OK. public tables: {len(tables)} | RLS-enabled: {rls_count}")
    print("tables:", ", ".join(tables))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
