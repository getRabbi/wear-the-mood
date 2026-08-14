"""CLI for the verified media backfill to R2 (INFRA_UPGRADE 1C).

Ops/dev tool — NOT shipped in any client. The reversible logic lives in
app.services.media.backfill (unit-tested); this just loads env, connects, runs.

Usage (run from backend/):
    python scripts/backfill_media.py                       # DRY RUN — counts only
    python scripts/backfill_media.py --migrate             # copy+verify+flip all
    python scripts/backfill_media.py --migrate --sector wardrobe_item --limit 200
    python scripts/backfill_media.py --legacy-gap          # DRY RUN — assets off the ledger
    python scripts/backfill_media.py --enrol-legacy        # put them ON it (adds rows, no objects)
    python scripts/backfill_media.py --thumbnails          # DRY RUN — missing-thumbnail counts
    python scripts/backfill_media.py --add-thumbnails      # generate+verify+record them
    python scripts/backfill_media.py --add-thumbnails --sector tryon_result
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
    --env .env.staging targets the staging buckets. Must run before get_settings.

    Missing or empty is FATAL rather than quiet. Silence here does not mean
    "use defaults", it means the process falls back to whatever `.env` happens
    to hold — which on a dev box is the dev database. A near-miss during the
    thumbnail backfill: a PowerShell-written env file carried a UTF-8 BOM, so
    the first key parsed as `\\ufeffCONNECTION_STRING`, nothing loaded, and a
    command aimed at production reported a clean zero from the DEV database. A
    dry run caught it; a mutation would not have been caught.
    """
    path = Path(__file__).resolve().parent.parent / env_file
    if not path.is_file():
        raise SystemExit(f"env file not found: {path}")
    # utf-8-sig strips a BOM if one is present and is identical to utf-8 if not.
    values = dotenv_values(path, encoding="utf-8-sig")
    loaded = 0
    for key, value in values.items():
        if value is not None:
            os.environ[key.lstrip("﻿")] = value
            loaded += 1
    if loaded == 0:
        raise SystemExit(f"env file loaded no values: {path}")


def _db_host(dsn: str) -> str:
    """Host (and database) the DSN points at — printed before anything is
    written, so 'which database was that?' is never a question afterwards."""
    from urllib.parse import urlsplit

    try:
        parts = urlsplit(dsn)
        return f"{parts.hostname}{parts.path}"
    except ValueError:
        return "<unparseable dsn>"


async def _run(args: argparse.Namespace) -> int:
    import asyncpg

    from app.core.config import get_settings
    from app.services.media import backfill

    settings = get_settings()
    if not settings.connection_string:
        print("CONNECTION_STRING not set — point --env at a configured env file.")
        return 2

    # Always, for every mode including a dry run: the target is the one fact
    # that must never be assumed.
    print(f"target -> env={settings.environment} db={_db_host(settings.connection_string)}")

    conn = await asyncpg.connect(
        dsn=settings.connection_string, statement_cache_size=0, ssl="require"
    )
    try:
        if args.rollback:
            n = await backfill.rollback(conn, args.sector)
            print(f"rolled back {n} row(s) to legacy (legacy_url intact, R2 kept).")
            return 0

        if args.enrol_legacy:
            cov = await backfill.enrol_unledgered_covers(conn)
            res = await backfill.enrol_unledgered_tryon_results(conn)
            for label, counts in (("ai covers", cov), ("tryon results", res)):
                print(
                    f"  {label:<15} enrolled={counts['enrolled']} "
                    f"skipped={counts['skipped']} unresolvable={counts['unresolvable']}"
                )
            print("next: --migrate --sector generated_image")
            print("      --migrate --sector tryon_result")
            return 0

        if args.legacy_gap:
            cov = await backfill.unledgered_cover_counts(conn)
            res = await backfill.unledgered_tryon_result_counts(conn)
            print("DRY RUN - assets that are OFF the media ledger (no changes made):")
            print(f"  {'':<16}{'total':>8}{'on ledger':>12}{'enrollable':>12}{'unresolvable':>14}")
            print(
                f"  {'ai covers':<16}{cov.get('covers', 0):>8}{cov.get('on_ledger', 0):>12}"
                f"{cov.get('enrollable', 0):>12}{cov.get('unresolvable', 0):>14}"
            )
            print(
                f"  {'tryon results':<16}{res.get('results', 0):>8}{res.get('on_ledger', 0):>12}"
                f"{res.get('enrollable', 0):>12}{res.get('unresolvable', 0):>14}"
            )
            return 0

        if args.add_thumbnails:
            if not settings.r2_configured:
                print("R2 not configured (need R2_ENDPOINT / keys / R2_PUBLIC_BASE_URL).")
                return 2
            print(
                f"adding thumbnails -> env={settings.environment} "
                f"private={settings.active_private_bucket}"
            )
            counts = await backfill.add_missing_thumbnails(conn, args.sector, args.limit)
            print(f"added={counts['added']} skipped={counts['skipped']} failed={counts['failed']}")
            return 0 if counts["failed"] == 0 else 1

        if args.thumbnails:
            rows = await backfill.missing_thumbnail_counts(conn, args.sector)
            total = 0
            print("DRY RUN - R2 objects with NO thumbnail (no changes made):")
            print(f"{'owner_kind':<18}{'role':<14}{'visibility':<12}{'count':>8}")
            for r in rows:
                total += r["n"]
                print(f"{r['owner_kind']:<18}{r['role']:<14}{r['visibility']:<12}{r['n']:>8}")
            print(f"{'TOTAL':<44}{total:>8}")
            return 0

        if args.migrate:
            if not settings.r2_configured:
                print("R2 not configured (need R2_ENDPOINT / keys / R2_PUBLIC_BASE_URL).")
                return 2
            print(
                f"migrating -> env={settings.environment} "
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
        print("DRY RUN - legacy images that WOULD migrate (no changes made):")
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
    p.add_argument("--thumbnails", action="store_true", help="count r2 objects missing a thumbnail")
    p.add_argument(
        "--legacy-gap",
        action="store_true",
        dest="legacy_gap",
        help="count AI covers / try-on results that are off the ledger entirely",
    )
    p.add_argument(
        "--enrol-legacy",
        action="store_true",
        dest="enrol_legacy",
        help="record pre-R2 covers + try-on results on the ledger so --migrate can move them",
    )
    p.add_argument(
        "--add-thumbnails",
        action="store_true",
        dest="add_thumbnails",
        help="generate+verify+record missing thumbnails (never touches the original)",
    )
    p.add_argument("--dry-run", action="store_true", help="counts only (default)")
    p.add_argument("--sector", default=None, help="filter by owner_kind")
    p.add_argument("--limit", type=int, default=100_000, help="max rows to migrate")
    args = p.parse_args()
    exclusive = [args.migrate, args.rollback, args.add_thumbnails, args.enrol_legacy]
    if sum(1 for flag in exclusive if flag) > 1:
        print("choose one of --migrate / --rollback / --add-thumbnails / --enrol-legacy.")
        return 2
    _load_env(args.env)
    return asyncio.run(_run(args))


if __name__ == "__main__":
    sys.exit(main())
