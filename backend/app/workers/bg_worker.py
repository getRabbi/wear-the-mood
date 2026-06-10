"""Wardrobe background-removal worker (Render worker, CLAUDE.md §2.2, §8).

Claims queued wardrobe_items one at a time (FOR UPDATE SKIP LOCKED so workers
never collide), downloads the original image, runs the BackgroundRemover,
uploads the cutout and sets cutout_url + thumbnail_url + status 'done'. Failures
mark the item 'failed' — the original image_url keeps displaying. Every attempt
is logged to ai_usage_log (§14); rembg is self-hosted, so estimated_usd is 0.
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

import asyncpg

from app.services.bg import get_background_remover
from app.services.storage import download_image, upload_cutout

log = logging.getLogger("fashionos.worker.bg")


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
        returning id, user_id, image_url
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
    success: bool,
    latency_ms: int,
) -> None:
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, images, estimated_usd, latency_ms, success)
        values ($1::uuid, $2, 'bg_removal', 1, $3, $4, $5)
        """,
        str(user_id),
        provider,
        Decimal("0"),
        latency_ms,
        success,
    )


async def process_item(conn: asyncpg.Connection, item: asyncpg.Record) -> None:
    item_id, user_id, image_url = item["id"], item["user_id"], item["image_url"]
    remover = get_background_remover()
    started = time.monotonic()

    try:
        original = await download_image(image_url)
        cutout = await remover.remove(original)
        cutout_url = await upload_cutout(str(user_id), cutout)
    except Exception as exc:  # download/model/upload error -> fail, keep original
        latency = int((time.monotonic() - started) * 1000)
        await _mark_failed(conn, item_id)
        await _log_usage(
            conn, user_id=user_id, provider=remover.name, success=False, latency_ms=latency
        )
        log.warning("bg removal for item %s failed: %s", item_id, exc)
        return

    latency = int((time.monotonic() - started) * 1000)
    await conn.execute(
        """
        update public.wardrobe_items
           set cutout_status = 'done',
               cutout_url = $2,
               thumbnail_url = coalesce(thumbnail_url, $2)
         where id = $1::uuid
        """,
        str(item_id),
        cutout_url,
    )
    await _log_usage(
        conn, user_id=user_id, provider=remover.name, success=True, latency_ms=latency
    )
    log.info("bg removal for item %s done", item_id)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued item. Returns True if one was processed."""
    item = await claim_next_item(conn)
    if item is None:
        return False
    await process_item(conn, item)
    return True
