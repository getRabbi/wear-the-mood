"""Quick DB sanity check against CONNECTION_STRING (ops/dev tool, not shipped).

Usage (run from backend/):  python scripts/verify_db.py
"""

from __future__ import annotations

from pathlib import Path

import psycopg
from dotenv import dotenv_values

dsn = dotenv_values(Path(__file__).resolve().parent.parent / ".env")["CONNECTION_STRING"]

with psycopg.connect(dsn, autocommit=True, prepare_threshold=None) as conn:
    cur = conn.cursor()

    cur.execute(
        "select extname from pg_extension where extname in ('vector', 'pgcrypto') order by extname"
    )
    print("extensions:", [r[0] for r in cur.fetchall()])

    cur.execute("select count(*) from pg_policies where schemaname = 'public'")
    print("policies:", cur.fetchone()[0])

    cur.execute("select tgname from pg_trigger where tgname = 'on_auth_user_created'")
    print("signup trigger present:", bool(cur.fetchall()))

    cur.execute(
        "select count(*) from pg_indexes where schemaname = 'public' and indexdef ilike '%hnsw%'"
    )
    print("hnsw vector indexes:", cur.fetchone()[0])
