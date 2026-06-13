"""Apply the baseline + every ordered migration to CONNECTION_STRING, in order.

Ops/dev tool only — NOT shipped in any client. Idempotent (safe to re-run). Point
CONNECTION_STRING (in the git-ignored backend/.env) at the TARGET database first.

Usage (run from backend/):
    python scripts/apply_all.py
"""

from __future__ import annotations

from pathlib import Path

import psycopg
from dotenv import dotenv_values


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent.parent
    supabase = repo_root / "supabase"
    files = [supabase / "FASHIONOS_BASELINE.sql"]
    files += sorted((supabase / "migrations").glob("*.sql"))  # 0001…0009, in order

    missing = [f for f in files if not f.exists()]
    if missing:
        print("missing files:", ", ".join(str(m) for m in missing))
        return 1

    dsn = dotenv_values(Path(__file__).resolve().parent.parent / ".env").get("CONNECTION_STRING")
    if not dsn:
        print("CONNECTION_STRING not set in backend/.env")
        return 1

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
                "select count(*) from pg_tables "
                "where schemaname = 'public' and rowsecurity = true"
            )
            rls = cur.fetchone()[0]
    print(f"OK. public tables: {tables} | RLS-enabled: {rls}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
