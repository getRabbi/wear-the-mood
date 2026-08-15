"""CLI for the canonical-category backfill (spec Phase 5 / Phase 25 step 3).

Ops/dev tool — NOT shipped in any client. The reversible logic lives in
app.services.tryon.backfill (unit-tested); this just loads env, connects, runs.

Usage (run from backend/):
    python scripts/backfill_canonical_category.py                    # DRY RUN, both tables
    python scripts/backfill_canonical_category.py --table products   # DRY RUN, one table
    python scripts/backfill_canonical_category.py --apply            # WRITE both
    python scripts/backfill_canonical_category.py --apply --table wardrobe_items --limit 500
    python scripts/backfill_canonical_category.py --rollback         # clear the derived columns
    python scripts/backfill_canonical_category.py --apply --env .env.staging

ORDER MATTERS (see supabase/migrations/0070_tryon_category_gate.sql):

    0069 -> deploy -> THIS --dry-run -> read the numbers -> THIS --apply -> 0070

Running 0070 before the apply would make every catalogue product try-on
ineligible until this catches up. Nothing here deletes a row or touches a
merchant's own `category` text, so `--rollback` restores the exact prior state.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from dotenv import dotenv_values

_TABLES = ("wardrobe_items", "products")


def _load_env(env_file: str) -> None:
    """Load the chosen env file into os.environ (wins over the default .env).

    Missing or empty is FATAL rather than quiet, for the reason recorded in
    scripts/backfill_media.py: a silent fallback to `.env` on a dev box makes a
    command aimed at production report a clean zero from the dev database.
    """
    path = Path(__file__).resolve().parent.parent / env_file
    if not path.is_file():
        raise SystemExit(f"env file not found: {path}")
    values = dotenv_values(path, encoding="utf-8-sig")
    loaded = 0
    for key, value in values.items():
        if value is not None:
            os.environ[key.lstrip("﻿")] = value
            loaded += 1
    if loaded == 0:
        raise SystemExit(f"env file loaded no values: {path}")


def _db_host(dsn: str) -> str:
    from urllib.parse import urlsplit

    try:
        parts = urlsplit(dsn)
        return f"{parts.hostname}{parts.path}"
    except ValueError:
        return "<unparseable dsn>"


async def _run(args: argparse.Namespace) -> int:
    import asyncpg

    from app.core.config import get_settings
    from app.services.tryon import backfill

    settings = get_settings()
    if not settings.connection_string:
        print("CONNECTION_STRING not set — point --env at a configured env file.")
        return 2

    # Printed for every mode including a dry run: the target is the one fact
    # that must never be assumed.
    print(f"target -> env={settings.environment} db={_db_host(settings.connection_string)}")
    tables = [args.table] if args.table else list(_TABLES)

    conn = await asyncpg.connect(
        dsn=settings.connection_string, statement_cache_size=0, ssl="require"
    )
    try:
        if args.rollback:
            for table in tables:
                n = await backfill.rollback(conn, table)
                print(f"{table}: cleared canonical_category on {n} row(s) (source data intact).")
            return 0

        if args.apply:
            for table in tables:
                counts = await backfill.apply(conn, table, limit=args.limit)
                print(
                    f"{table}: classified={counts['classified']} "
                    f"needs_review={counts['needs_review']}"
                )
            print("next: apply supabase/migrations/0070_tryon_category_gate.sql")
            return 0

        print("DRY RUN — no changes made.")
        for table in tables:
            print((await backfill.report(conn, table)).render())
        print("\nreview the assignments above, then re-run with --apply")
        return 0
    finally:
        await conn.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="WRITE the classifications")
    parser.add_argument("--rollback", action="store_true", help="clear the derived columns")
    parser.add_argument("--table", choices=_TABLES, help="one table (default: both)")
    parser.add_argument("--limit", type=int, default=None, help="max rows per table with --apply")
    parser.add_argument("--env", default=".env", help="env file to load (default .env)")
    args = parser.parse_args()
    if args.apply and args.rollback:
        parser.error("--apply and --rollback are mutually exclusive")
    _load_env(args.env)
    return asyncio.run(_run(args))


if __name__ == "__main__":
    sys.exit(main())
