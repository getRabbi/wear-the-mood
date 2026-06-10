"""Wardrobe enrichment worker (Render worker, CLAUDE.md §2.1, §2.2, §8).

Claims queued wardrobe_items one at a time (FOR UPDATE SKIP LOCKED), then runs
the enrichment pipeline: background removal -> cutout upload -> auto-tagging.
Cutout failure marks the item 'failed' (original keeps displaying); tagging is
best-effort and only fills empty attributes (never overwrites the user's). Every
AI call is logged to ai_usage_log (§14). Embeddings join this pipeline next.
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

import asyncpg

from app.services.bg import get_background_remover
from app.services.llm import get_embedder, get_garment_tagger
from app.services.llm.base import GarmentTags
from app.services.storage import download_image, upload_cutout

log = logging.getLogger("fashionos.worker.bg")

# Rough Claude Haiku-class vision rate for cost visibility (§14); refine later.
_TAG_USD_PER_INPUT_TOK = Decimal("1") / Decimal("1000000")
_TAG_USD_PER_OUTPUT_TOK = Decimal("5") / Decimal("1000000")

_DONE_UPDATE = """
    update public.wardrobe_items
       set cutout_status = 'done',
           cutout_url = $2,
           thumbnail_url = coalesce(thumbnail_url, $2),
           category = coalesce(category, $3),
           subcategory = coalesce(subcategory, $4),
           color = coalesce(color, $5),
           pattern = coalesce(pattern, $6),
           tags = case when cardinality($7::text[]) > 0 then $7::text[] else tags end
     where id = $1::uuid
"""


def _ms(start: float) -> int:
    return int((time.monotonic() - start) * 1000)


def _tag_cost(tags: GarmentTags) -> Decimal:
    if tags.input_tokens is None:
        return Decimal("0")
    return (
        Decimal(tags.input_tokens) * _TAG_USD_PER_INPUT_TOK
        + Decimal(tags.output_tokens or 0) * _TAG_USD_PER_OUTPUT_TOK
    )


async def claim_next_item(conn: asyncpg.Connection) -> asyncpg.Record | None:
    """Atomically claim the oldest queued item, flipping it to 'processing'."""
    return await conn.fetchrow(
        """
        update public.wardrobe_items
           set cutout_status = 'processing'
         where id = (
           select id
             from public.wardrobe_items
            where cutout_status = 'queued'
            order by created_at
            for update skip locked
            limit 1
         )
        returning id, user_id, image_url, title, category
        """
    )


async def _mark_failed(conn: asyncpg.Connection, item_id: object) -> None:
    await conn.execute(
        "update public.wardrobe_items set cutout_status = 'failed' where id = $1::uuid",
        str(item_id),
    )


async def _log_usage(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    provider: str,
    task: str,
    success: bool,
    latency_ms: int,
    images: int = 0,
    input_tokens: int | None = None,
    output_tokens: int | None = None,
    estimated_usd: Decimal = Decimal("0"),
) -> None:
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, input_tokens, output_tokens, images,
           estimated_usd, latency_ms, success)
        values ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9)
        """,
        str(user_id),
        provider,
        task,
        input_tokens,
        output_tokens,
        images,
        estimated_usd,
        latency_ms,
        success,
    )


async def process_item(conn: asyncpg.Connection, item: asyncpg.Record) -> None:
    item_id, user_id, image_url = item["id"], item["user_id"], item["image_url"]

    # 1. Background removal — required; failure keeps the original image.
    remover = get_background_remover()
    started = time.monotonic()
    try:
        original = await download_image(image_url)
        cutout = await remover.remove(original)
        cutout_url = await upload_cutout(str(user_id), cutout)
    except Exception as exc:
        await _mark_failed(conn, item_id)
        await _log_usage(
            conn, user_id=user_id, provider=remover.name, task="bg_removal",
            success=False, latency_ms=_ms(started),
        )
        log.warning("bg removal for item %s failed: %s", item_id, exc)
        return
    await _log_usage(
        conn, user_id=user_id, provider=remover.name, task="bg_removal",
        success=True, latency_ms=_ms(started), images=1,
    )

    # 2. Auto-tagging — best-effort (§2.1); only fills empty attributes below.
    tagger = get_garment_tagger()
    tag_started = time.monotonic()
    tags: GarmentTags | None = None
    try:
        tags = await tagger.tag(cutout, "image/png")
        await _log_usage(
            conn, user_id=user_id, provider=tagger.name, task="tagging",
            success=True, latency_ms=_ms(tag_started), images=1,
            input_tokens=tags.input_tokens, output_tokens=tags.output_tokens,
            estimated_usd=_tag_cost(tags),
        )
    except Exception as exc:
        await _log_usage(
            conn, user_id=user_id, provider=tagger.name, task="tagging",
            success=False, latency_ms=_ms(tag_started),
        )
        log.warning("tagging for item %s failed: %s", item_id, exc)

    # 3. Persist cutout + (gap-filled) attributes.
    await conn.execute(
        _DONE_UPDATE,
        str(item_id),
        cutout_url,
        tags.category if tags else None,
        tags.subcategory if tags else None,
        tags.color if tags else None,
        tags.pattern if tags else None,
        list(tags.tags) if tags else [],
    )

    # 4. Embedding — best-effort (§2.1); powers semantic closet search + taste.
    await _embed_item(conn, item, tags)
    log.info("enrichment for item %s done", item_id)


def _embed_text(item: asyncpg.Record, tags: GarmentTags | None) -> str:
    parts = [item["title"], item["category"]]
    if tags is not None:
        parts += [tags.category, tags.subcategory, tags.color, tags.pattern, *tags.tags]
    # De-dupe while preserving order, drop blanks.
    seen: dict[str, None] = {}
    for p in parts:
        if p and p.strip():
            seen.setdefault(p.strip(), None)
    return " ".join(seen)


async def _embed_item(
    conn: asyncpg.Connection, item: asyncpg.Record, tags: GarmentTags | None
) -> None:
    embedder = get_embedder()
    text = _embed_text(item, tags)
    # Stub embedder is a no-op; nothing meaningful to store without text/a key.
    if embedder.name == "stub" or not text:
        return

    started = time.monotonic()
    try:
        vector = await embedder.embed(text)
        vec_literal = "[" + ",".join(repr(float(x)) for x in vector) + "]"
        await conn.execute(
            "update public.wardrobe_items set embedding = $2::vector where id = $1::uuid",
            str(item["id"]),
            vec_literal,
        )
        await _log_usage(
            conn, user_id=item["user_id"], provider=embedder.name, task="embedding",
            success=True, latency_ms=_ms(started),
        )
    except Exception as exc:
        await _log_usage(
            conn, user_id=item["user_id"], provider=embedder.name, task="embedding",
            success=False, latency_ms=_ms(started),
        )
        log.warning("embedding for item %s failed: %s", item["id"], exc)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued item. Returns True if one was processed."""
    item = await claim_next_item(conn)
    if item is None:
        return False
    await process_item(conn, item)
    return True
