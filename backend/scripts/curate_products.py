"""Curate NAMED products from an affiliate feed into the catalog. Ops tool.

The importer is built to sync a whole feed. That is the wrong instrument for a
launch seed: an accidental unrestricted run against AliExpress writes six figures
of rows, and undoing that in production is not a five-minute job. This selects a
short list of products BY ID and refuses to write anything else.

It is not a second import path. Rows go through the same adapter -> mapping ->
normalize pipeline and the same ``_upsert_product`` the cron uses, under a real
``product_sync_runs`` row, so provenance and bookkeeping look exactly as they
would for an automated import. The only differences are which rows are chosen
and that each one is frozen with ``manual_override`` afterwards.

Product data is never hardcoded here — ids come from the command line and every
field comes from the live feed.

Usage (from backend/):
    python scripts/curate_products.py --network awin \\
        --pick 21667:1005007604979654 --pick 21695:1005012382038494 \\
        --expect 2 --reason "launch seed"

    python scripts/curate_products.py ... --dry-run     # parse + report, no write
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import asyncpg  # noqa: E402
from dotenv import dotenv_values  # noqa: E402

from app.services.catalog.mapping import apply_mapping  # noqa: E402
from app.services.catalog.models import SyncCounts  # noqa: E402
from app.services.catalog.networks.awin import AwinClient, read_feed  # noqa: E402
from app.services.catalog.networks.awin_adapter import awin_row_to_canonical  # noqa: E402
from app.services.catalog.normalize import FeedRecordError, normalize  # noqa: E402
from app.services.catalog.sync import _as_dict, _upsert_product  # noqa: E402

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _dsn(env_path: Path) -> str:
    env = dotenv_values(env_path)
    dsn = env.get("CONNECTION_STRING_DIRECT") or env.get("CONNECTION_STRING")
    if not dsn:
        raise SystemExit("no CONNECTION_STRING(_DIRECT) in backend/.env")
    return dsn


def _load_network_credentials() -> None:
    """Put the feed credentials where the connector reads them.

    In production these are real process env vars on the job; run as a script
    they live in the git-ignored backend/.env. Never printed — the connector
    silences httpx at import for exactly this reason (0065-era fix).
    """
    import os

    env = dotenv_values(_ENV_FILE)
    for key in ("AWIN_PUBLISHER_ID", "AWIN_DATA_FEED_API_KEY"):
        if not os.environ.get(key) and env.get(key):
            os.environ[key] = env[key]


async def _run(args: argparse.Namespace) -> int:
    wanted: dict[str, list[str]] = {}
    for pick in args.pick:
        feed, _, ext = pick.partition(":")
        if not feed or not ext:
            raise SystemExit(f"--pick must be FEED_ID:EXTERNAL_ID, got {pick!r}")
        wanted.setdefault(feed, []).append(ext)
    total_wanted = sum(len(v) for v in wanted.values())

    # The guard that makes this safe to run against production. `--expect` is
    # stated by the operator BEFORE anything is read, so a feed that happens to
    # contain more matches than intended cannot quietly widen the write.
    if total_wanted != args.expect:
        raise SystemExit(f"--expect {args.expect} but {total_wanted} ids were given")

    _load_network_credentials()
    conn = await asyncpg.connect(args.dsn or _dsn(_ENV_FILE))
    try:
        merchant = await conn.fetchrow(
            "select id, name from public.merchants where network = $1 limit 1", args.network
        )
        if merchant is None:
            raise SystemExit(f"no merchant for network {args.network!r} — run discovery first")
        merchant_id = str(merchant["id"])
        print(f"[merchant] {merchant['name']}  {merchant_id}")

        cfg = await conn.fetchrow(
            "select image_rights_default, price_format, default_currency, field_map, stock_map"
            "  from public.merchant_feed_config where merchant_id = $1",
            merchant_id,
        )
        if cfg is None:
            raise SystemExit("merchant has no merchant_feed_config row")
        mapping_config = {
            "price_format": cfg["price_format"],
            "default_currency": cfg["default_currency"],
            # jsonb arrives as a string from asyncpg without a codec; the
            # importer's own helper decodes it, so both paths agree.
            "field_map": _as_dict(cfg["field_map"]),
            "stock_map": _as_dict(cfg["stock_map"]),
        }
        rights_default = cfg["image_rights_default"] or "unknown"
        print(f"[config]   price_format={mapping_config['price_format']} rights={rights_default}")

        # Read only the feeds that were actually named.
        selected = []
        client = AwinClient()
        for feed_id, ids in wanted.items():
            res = await read_feed(None, client.feed_url(feed_id, language="en"), feed_id)
            if not res.complete:
                raise SystemExit(f"feed {feed_id} did not read completely: {res.error}")
            found: dict[str, object] = {}
            for raw in res.rows:
                try:
                    p = normalize(apply_mapping(awin_row_to_canonical(raw), mapping_config))
                except FeedRecordError:
                    continue
                if p.external_id in ids and p.external_id not in found:
                    found[p.external_id] = p
            missing = [i for i in ids if i not in found]
            if missing:
                raise SystemExit(f"feed {feed_id}: ids not found -> {missing}")
            print(f"[feed {feed_id}] rows={len(res.rows)} matched={len(found)}")
            selected.extend(found[i] for i in ids)

        # Second guard, after parsing and before the transaction.
        if len(selected) != args.expect:
            raise SystemExit(f"selected {len(selected)} products, expected {args.expect}")

        for p in selected:
            print(f"    {p.external_id:<18} {p.price_minor:>8} {p.currency}  {p.title[:64]}")

        if args.dry_run:
            print(f"\n[dry-run] would write {len(selected)} product(s); nothing changed.")
            return 0

        counts = SyncCounts()
        async with conn.transaction():
            run_id = str(
                await conn.fetchval(
                    """
                    insert into public.product_sync_runs
                      (merchant_id, status, trigger_source, triggered_by, dry_run, started_at)
                    values ($1, 'running', 'admin', $2, false, now()) returning id
                    """,
                    merchant_id,
                    args.reason,
                )
            )
            for p in selected:
                existing = await conn.fetchrow(
                    "select id, external_id, source_hash, active, manual_override,"
                    "       manual_override_fields, deactivated_by_sync_at"
                    "  from public.products where merchant_id = $1 and external_id = $2",
                    merchant_id,
                    p.external_id,
                )
                await _upsert_product(
                    conn, merchant_id, run_id, p, rights_default, counts, existing=existing
                )

            # Freeze the whole row. These are editorial choices, not a feed
            # snapshot: a later sync must not requote them, and absence from a
            # feed must not retire them.
            await conn.execute(
                """
                update public.products
                   set manual_override = true,
                       manual_override_fields = '{}',
                       manual_override_by = $3,
                       manual_override_at = now(),
                       updated_at = now()
                 where merchant_id = $1 and external_id = any($2::text[])
                """,
                merchant_id,
                [p.external_id for p in selected],
                args.reason,
            )
            # Counted with a separate read AFTER the update. A `returning` that
            # embeds its own count subquery reads the pre-update snapshot and
            # cheerfully reports 0 — an ops tool that misreports what it just
            # did is worse than one that prints nothing.
            frozen = await conn.fetchval(
                "select count(*) from public.products"
                " where merchant_id = $1 and external_id = any($2::text[]) and manual_override",
                merchant_id,
                [p.external_id for p in selected],
            )

            total = await conn.fetchval(
                "select count(*) from public.products where merchant_id = $1", merchant_id
            )
            # Last line of defence: if this merchant somehow holds more rows than
            # the operator declared, roll the whole thing back.
            if args.max_total is not None and total > args.max_total:
                raise SystemExit(
                    f"ABORT: merchant would hold {total} products, --max-total is {args.max_total}"
                )

            await conn.execute(
                "update public.product_sync_runs set status='success', finished_at=now(),"
                "       fetched=$2, created=$3, updated=$4, unchanged=$5, source_complete=true"
                " where id=$1",
                run_id,
                len(selected),
                counts.created,
                counts.updated,
                counts.unchanged,
            )

        print(
            f"\n[written] created={counts.created} updated={counts.updated} "
            f"unchanged={counts.unchanged} frozen={frozen}"
        )
        print(f"[total]   products for this merchant = {total}")
        return 0
    finally:
        await conn.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--network", default="awin")
    ap.add_argument("--pick", action="append", required=True, metavar="FEED_ID:EXTERNAL_ID")
    ap.add_argument("--expect", type=int, required=True, help="how many rows you intend to write")
    ap.add_argument(
        "--max-total", type=int, default=None, help="abort if the merchant exceeds this"
    )
    ap.add_argument("--reason", default="curated launch seed")
    ap.add_argument("--dsn", default=None)
    ap.add_argument("--dry-run", action="store_true")
    return asyncio.run(_run(ap.parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
