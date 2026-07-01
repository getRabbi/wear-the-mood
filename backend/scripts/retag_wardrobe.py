"""Re-tag wardrobe items whose Claude-vision auto-tagging was skipped or failed
(e.g. items added while the Anthropic account had no credits, CLAUDE.md §2.1).

It re-runs tagging + embedding on the item's EXISTING cutout — it never re-does
background removal — and only fills attributes the user left blank (the tag
UPDATE `coalesce`s), so it is safe to re-run and won't clobber manual edits.

Run it INSIDE the worker container on the droplet AFTER topping up Anthropic
credits (the container already has CONNECTION_STRING_DIRECT + ANTHROPIC_API_KEY):

    # From the droplet, in /root/fashionos:
    docker compose exec worker python scripts/retag_wardrobe.py --dry-run
    docker compose exec worker python scripts/retag_wardrobe.py --limit 300
    docker compose exec worker python scripts/retag_wardrobe.py --user <uuid>
    docker compose exec worker python scripts/retag_wardrobe.py --all --limit 500

Flags:
    --dry-run   list what WOULD be re-tagged; no API calls, no writes.
    --limit N   cap the batch (default 200).
    --user ID   only that user's closet.
    --all       re-tag every cutout-done item, not just the untagged ones.
    --delay S   seconds between items to stay gentle on the API (default 0.4).
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import asyncpg  # noqa: E402

from app.core.config import get_settings, is_secret_set  # noqa: E402
from app.services.llm import get_garment_tagger  # noqa: E402
from app.services.llm.base import GarmentTagger  # noqa: E402
from app.services.media.repo import resolve_images  # noqa: E402
from app.services.storage import download_image  # noqa: E402
from app.workers.bg_worker import (  # noqa: E402
    _TAGS_UPDATE,
    _embed_item,
    _log_usage,
    _ms,
    _tag_cost,
)

log = logging.getLogger("fashionos.retag")
logging.basicConfig(level=logging.INFO, format="%(message)s")

# Strong signal that vision tagging never succeeded: no color AND no tags — both
# come ONLY from the tagger (category can be user-set, so it isn't used alone).
_UNTAGGED = "(color is null and coalesce(cardinality(tags), 0) = 0)"


def _candidates_sql(*, all_items: bool, by_user: bool) -> str:
    where = ["cutout_status = 'done'"]
    if not all_items:
        where.append(_UNTAGGED)
    if by_user:
        where.append("user_id = $2::uuid")
    return (
        "select id, user_id, title, category, image_url, cutout_url "
        "from public.wardrobe_items "
        f"where {' and '.join(where)} "
        "order by created_at desc limit $1"
    )


async def _tag_source_url(conn: asyncpg.Connection, item: asyncpg.Record) -> str | None:
    """Prefer the clean cutout (R2 signed / legacy url); fall back to the original."""
    m = await resolve_images(conn, "wardrobe_item", [item["id"]], ("cutout",))
    hit = m.get((str(item["id"]), "cutout"))
    if hit and hit.url:
        return hit.url
    return item["cutout_url"] or item["image_url"]


async def _retag_one(
    conn: asyncpg.Connection, tagger: GarmentTagger, item: asyncpg.Record
) -> bool:
    url = await _tag_source_url(conn, item)
    if not url:
        log.info("  · %s — no image, skipped", item["id"])
        return False
    started = time.monotonic()
    try:
        image = await download_image(url)
        tags = await tagger.tag(image, "image/png")
    except Exception as exc:  # noqa: BLE001 — best-effort, keep going
        await _log_usage(
            conn,
            user_id=item["user_id"],
            provider=tagger.name,
            task="tagging",
            success=False,
            latency_ms=_ms(started),
        )
        log.info("  × %s — tag failed: %s", item["id"], exc)
        return False

    await conn.execute(
        _TAGS_UPDATE,
        str(item["id"]),
        tags.category,
        tags.subcategory,
        tags.color,
        tags.pattern,
        list(tags.tags),
    )
    await _log_usage(
        conn,
        user_id=item["user_id"],
        provider=tagger.name,
        task="tagging",
        success=True,
        latency_ms=_ms(started),
        images=1,
        input_tokens=tags.input_tokens,
        output_tokens=tags.output_tokens,
        estimated_usd=_tag_cost(tags),
    )
    await _embed_item(conn, item, tags)
    log.info(
        "  ✓ %s — %s / %s / %s  tags=%s",
        item["id"],
        tags.category,
        tags.subcategory,
        tags.color,
        list(tags.tags),
    )
    return True


async def main() -> int:
    ap = argparse.ArgumentParser(description="Re-tag wardrobe items (Claude vision).")
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--user", default=None, help="only this user_id")
    ap.add_argument(
        "--all",
        action="store_true",
        help="re-tag ALL cutout-done items, not just the untagged ones",
    )
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--delay", type=float, default=0.4, help="seconds between items (rate limit)"
    )
    args = ap.parse_args()

    dsn = os.environ.get("CONNECTION_STRING_DIRECT") or os.environ.get(
        "CONNECTION_STRING"
    )
    if not dsn:
        print(
            "No CONNECTION_STRING(_DIRECT) in the environment — run this INSIDE the "
            "worker container:  docker compose exec worker python scripts/retag_wardrobe.py"
        )
        return 1

    tagger = get_garment_tagger()
    if not is_secret_set(get_settings().anthropic_api_key) or tagger.name == "stub":
        print(
            "ANTHROPIC_API_KEY not set (tagger is the stub) — add the key/credits first."
        )
        return 1

    conn = await asyncpg.connect(dsn)
    try:
        sql = _candidates_sql(all_items=args.all, by_user=bool(args.user))
        params: list[object] = [args.limit]
        if args.user:
            params.append(args.user)
        rows = await conn.fetch(sql, *params)

        scope = "ALL cutout-done" if args.all else "untagged"
        who = f" for user {args.user}" if args.user else ""
        print(f"Found {len(rows)} {scope} item(s){who} to re-tag (provider={tagger.name}).")

        if args.dry_run:
            for r in rows:
                print(f"  - {r['id']}  title={r['title']!r}  category={r['category']!r}")
            print("dry-run: no API calls, no changes made.")
            return 0

        ok = 0
        for i, r in enumerate(rows, 1):
            print(f"[{i}/{len(rows)}] {r['id']}")
            if await _retag_one(conn, tagger, r):
                ok += 1
            if args.delay:
                await asyncio.sleep(args.delay)
        print(f"Done. Re-tagged {ok}/{len(rows)} item(s).")
        return 0
    finally:
        await conn.close()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
