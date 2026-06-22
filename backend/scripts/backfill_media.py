"""CLI for the verified media backfill to R2 (INFRA_UPGRADE 1C).

Ops/dev tool — NOT shipped in any client. The reversible logic lives in
app.services.media.backfill (unit-tested); this just loads env, connects, runs.

Usage (run from backend/):
    python scripts/backfill_media.py                       # DRY RUN — counts only
    python scripts/backfill_media.py --migrate             # copy+verify+flip all
    python scripts/backfill_media.py --migrate --sector wardrobe_item --limit 200
    python scripts/backfill_media.py --rollback            # flip r2 rows back to legacy
    python scripts/backfill_media.py --migrate --env .env.staging   # target staging R2

ALWAYS dry-run first, and run against the -staging buckets before prod. The
command never deletes old objects and keeps legacy_url intact (lossless rollback).
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from dotenv import dotenv_values


def _load_env(env_file: str) -> None:
    """Load the chosen env file into os.environ (wins over the default .env) so
    --env .env.staging targets the staging buckets. Must run before get_settings."""
    path = Path(__file__).resolve().parent.parent / env_file
    for key, value in dotenv_values(path).items():
        if value is not None:
            os.environ[key] = value


async def _run(args: argparse.Namespace) -> int:
    import asyncpg

    from app.core.config import get_settings
    from app.services.media import backfill

    settings = get_settings()
    if not settings.connection_string:
        print("CONNECTION_STRING not set — point --env at a configured env file.")
        return 2

    conn = await asyncpg.connect(
        dsn=settings.connection_string, statement_cache_size=0, ssl="require"
    )
    try:
        if args.rollback:
            n = await backfill.rollback(conn, args.sector)
            print(f"rolled back {n} row(s) to legacy (legacy_url intact, R2 kept).")
            return 0

        if args.migrate:
            if not settings.r2_configured:
                print("R2 not configured (need R2_ENDPOINT / keys / R2_PUBLIC_BASE_URL).")
                return 2
            print(
                f"migrating → env={settings.environment} "
                f"public={settings.active_public_bucket} "
                f"private={settings.active_private_bucket}"
            )
            counts = await backfill.migrate(conn, args.sector, args.limit)
            print(
                f"migrated={counts['migrated']} skipped={counts['skipped']} "
                f"failed={counts['failed']}"
            )
            return 0 if counts["failed"] == 0 else 1

        # default: DRY RUN
        rows = await backfill.dry_run_counts(conn, args.sector)
        total = 0
        print("DRY RUN — legacy images that WOULD migrate (no changes made):")
        print(f"{'owner_kind':<16}{'role':<12}{'visibility':<10}{'count':>8}")
        for r in rows:
            total += r["n"]
            print(f"{r['owner_kind']:<16}{r['role']:<12}{r['visibility']:<10}{r['n']:>8}")
        print(f"{'TOTAL':<38}{total:>8}")
        return 0
    finally:
        await conn.close()


def main() -> int:
    p = argparse.ArgumentParser(description="Verified media backfill to R2 (1C).")
    p.add_argument("--env", default=".env", help="env file under backend/ (default .env)")
    p.add_argument("--migrate", action="store_true", help="copy+verify+flip legacy rows")
    p.add_argument("--rollback", action="store_true", help="flip r2 rows back to legacy")
    p.add_argument("--dry-run", action="store_true", help="counts only (default)")
    p.add_argument("--sector", default=None, help="filter by owner_kind")
    p.add_argument("--limit", type=int, default=100_000, help="max rows to migrate")
    args = p.parse_args()
    if args.migrate and args.rollback:
        print("choose one of --migrate / --rollback.")
        return 2
    _load_env(args.env)
    return asyncio.run(_run(args))


if __name__ == "__main__":
    sys.exit(main())
