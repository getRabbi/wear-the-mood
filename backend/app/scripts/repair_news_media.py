"""Re-resolve hero images for news stories already in the database (Issue 3).

Ingestion now resolves and validates media as it writes, but every row that
landed BEFORE that has an unvalidated `image_url` and a null `image_status`:
Vogue rows that happen to work, Hypebeast rows that were never given the chance,
Highsnobiety rows that never had a picture because nobody fetched the page.

This walks those rows through the SAME resolver the pipeline uses and records
what it found.

    Dry run (default — reads only, writes nothing):
        python -m app.scripts.repair_news_media

    Per-source breakdown of what a dry run would do:
        python -m app.scripts.repair_news_media --report

    Apply, in batches, resumable:
        python -m app.scripts.repair_news_media --apply --batch 50 --limit 500

Properties, all deliberate:

* **Dry-run first.** `--apply` is required to write anything at all.
* **Idempotent.** Re-running re-resolves and re-writes the same answer; nothing
  accumulates and nothing double-counts.
* **Resumable.** Work is selected by `image_status is null` (or `--recheck`),
  and each batch commits on its own, so an interrupted run simply resumes.
* **Non-destructive.** It touches ONLY the image columns. Titles, links,
  summaries, canonical urls and editorial status are never rewritten — a repair
  that edits an editor's copy is not a repair.
* **Copies nothing.** No publisher image is downloaded into Wear The Mood
  storage. Sources are `external_hotlink_only` by default (0072) and this tool
  has no code path that uploads, whatever that column says.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
from collections import defaultdict

import asyncpg

from app.core.config import pick_migration_dsn
from app.services.news.media import (
    STATUS_OK,
    build_client,
    resolve_article_media,
)

log = logging.getLogger("fashionos.news.repair")

#: Rows never resolved (pre-0072). The normal worklist.
_UNRESOLVED = "image_status is null"
#: Rows whose last resolution FAILED. Worth another look — a publisher outage,
#: an expired CDN link or a since-fixed page all recover on their own.
_RECHECKABLE = "image_status is not null and image_status <> 'ok'"

_SELECT = """
    select i.id, i.url, i.canonical_url, i.image_url, i.image_status,
           coalesce(s.name, i.source, 'unknown') as source_name
      from public.news_items i
      left join public.news_sources s on s.id = i.source_id
     where {predicate}
     order by coalesce(i.published_at, i.created_at) desc
     limit $1
"""

_UPDATE = """
    update public.news_items
       set image_url = case when $2::text = 'ok' then $3::text else image_url end,
           image_source_url = coalesce(image_source_url, image_url),
           image_provenance = $4::text,
           image_status = $2::text,
           image_width = $5::int,
           image_height = $6::int,
           image_status_detail = $7::text,
           image_validated_at = now()
     where id = $1::uuid
"""


async def _rows(conn: asyncpg.Connection, *, recheck: bool, limit: int) -> list[asyncpg.Record]:
    predicate = f"({_UNRESOLVED} or {_RECHECKABLE})" if recheck else _UNRESOLVED
    return list(await conn.fetch(_SELECT.format(predicate=predicate), limit))


async def repair(
    conn: asyncpg.Connection,
    *,
    apply: bool,
    limit: int,
    batch: int,
    recheck: bool,
    resolver=None,
) -> dict[str, object]:
    """Resolve up to [limit] rows. Returns the counts a report is built from."""
    rows = await _rows(conn, recheck=recheck, limit=limit)
    resolve = resolver or resolve_article_media
    client = build_client() if resolver is None else None

    totals: dict[str, int] = defaultdict(int)
    per_source: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    try:
        for index, row in enumerate(rows):
            source = row["source_name"]
            per_source[source]["active"] += 1
            had_image = bool(row["image_url"])

            media = await resolve(
                entry=None,  # the feed entry is long gone; the page is what is left
                body="",
                article_url=row["url"] or row["canonical_url"] or "",
                client=client,
            )
            totals[media.status] += 1
            per_source[source][media.status] += 1
            if media.ok and not had_image:
                totals["recovered"] += 1
                per_source[source]["recovered"] += 1

            if apply:
                await conn.execute(
                    _UPDATE,
                    row["id"],
                    media.status,
                    media.url,
                    media.provenance,
                    media.width,
                    media.height,
                    (media.detail or "")[:400] or None,
                )
                totals["written"] += 1
            if batch and index and index % batch == 0:
                log.info("repaired %d/%d rows", index, len(rows))
    finally:
        if client is not None:
            await client.aclose()

    return {
        "examined": len(rows),
        "totals": dict(totals),
        "per_source": {k: dict(v) for k, v in per_source.items()},
        "applied": apply,
    }


def format_report(result: dict[str, object]) -> str:
    """The per-source table the final report asks for."""
    per_source: dict[str, dict[str, int]] = result["per_source"]  # type: ignore[assignment]
    header = f"{'Source':<24}{'Active':>8}{'Image OK':>10}{'Recovered':>11}{'Placeholder':>13}"
    lines = [header, "-" * len(header)]
    for name in sorted(per_source):
        counts = per_source[name]
        active = counts.get("active", 0)
        ok = counts.get(STATUS_OK, 0)
        lines.append(
            f"{name[:23]:<24}{active:>8}{ok:>10}{counts.get('recovered', 0):>11}{active - ok:>13}"
        )
    totals: dict[str, int] = result["totals"]  # type: ignore[assignment]
    lines.append("")
    lines.append(f"examined={result['examined']} applied={result['applied']}")
    lines.append("  ".join(f"{k}={v}" for k, v in sorted(totals.items())) or "  (nothing resolved)")
    return "\n".join(lines)


async def _main(args: argparse.Namespace) -> None:
    # Same DSN choice every admin script makes: the DIRECT 5432 connection when
    # it is configured, else the runtime pooler.
    dsn, _fallback = pick_migration_dsn(os.environ)
    if not dsn:
        raise SystemExit(
            "No database DSN configured (CONNECTION_STRING_DIRECT / CONNECTION_STRING)."
        )
    conn = await asyncpg.connect(dsn)
    try:
        result = await repair(
            conn,
            apply=args.apply,
            limit=args.limit,
            batch=args.batch,
            recheck=args.recheck,
        )
    finally:
        await conn.close()
    print(format_report(result))
    if not args.apply:
        print("\nDRY RUN — nothing was written. Re-run with --apply to persist.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the resolved media. Without this the run is read-only.",
    )
    parser.add_argument("--limit", type=int, default=200, help="Max rows to examine.")
    parser.add_argument("--batch", type=int, default=50, help="Progress log interval.")
    parser.add_argument(
        "--recheck",
        action="store_true",
        help="Also revisit rows whose last resolution failed.",
    )
    parser.add_argument("--report", action="store_true", help="Print the per-source table.")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(_main(args))


if __name__ == "__main__":
    main()
