"""Apply a .sql file to the database in CONNECTION_STRING.

Ops/dev tool only — NOT shipped in any client. Reads CONNECTION_STRING from
the git-ignored backend/.env.

Usage (run from backend/):
    python scripts/apply_sql.py ../supabase/FASHIONOS_BASELINE.sql
"""

from __future__ import annotations

import sys
from pathlib import Path

import psycopg
from dotenv import dotenv_values


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
    dsn = env.get("CONNECTION_STRING")
    if not dsn:
        print("CONNECTION_STRING not set in backend/.env")
        return 1

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
