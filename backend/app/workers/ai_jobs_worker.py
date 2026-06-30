"""AI Studio job draining (BUILD_PROMPT_PRO_PROMAX.md — shared ai_jobs system).

Claims queued `ai_jobs` one at a time (FOR UPDATE SKIP LOCKED so multiple workers
never grab the same row), runs the right premium AI feature, stores the output and
marks the job completed — keeping the credit RESERVED at submit (§7). Provider
failures mark the job failed and REFUND the reserved credit (never charge on
failure). Every attempt is logged to ai_usage_log (§14).

Job types handled here:
  * enhance_item  — ImageEnhancer.enhance() on the item's cutout (config-gated:
                    no real provider yet → fails cleanly + refunds, never fakes).
  * catalog_model — the garment on a studio model via the existing TryOnProvider
                    (FASHN). Live only when an active catalog preset image exists.

Try-on itself (own_photo / studio_model) runs on tryon_jobs / tryon_worker, NOT
here — see app.workers.tryon_worker.
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

import asyncpg

from app.core.config import get_settings
from app.core.credits import refund_credit
from app.services.imagegen import get_image_enhancer
from app.services.imagegen.base import ImageGenError, ImageGenNotConfigured
from app.services.media import get_storage_provider
from app.services.media.repo import insert_asset, resolve_images
from app.services.storage import download_image, upload_private_image
from app.services.tryon import get_tryon_provider
from app.services.tryon.base import TryOnError

log = logging.getLogger("fashionos.worker.ai_jobs")

# Private bucket reused for AI Studio outputs in legacy (non-R2) mode — already
# provisioned; the serve endpoint signs it. R2 mode stores under the private R2
# bucket via the StorageProvider.
_GENERATED_BUCKET = "tryon-results"

_PROVIDER_USD: dict[str, Decimal] = {"stub": Decimal("0"), "fashn": Decimal("0.075")}

# Clean, user-safe message when the catalog model isn't available (no active
# preset image yet). The reserved credit is refunded.
_CATALOG_UNAVAILABLE = (
    "Catalog model shots aren't available yet. Your credit was not used."
)


async def claim_next_ai_job(conn: asyncpg.Connection) -> asyncpg.Record | None:
    """Atomically claim the oldest queued ai_job, flipping it to 'processing'."""
    return await conn.fetchrow(
        """
        update public.ai_jobs
           set status = 'processing'
         where id = (
           select id
             from public.ai_jobs
            where status = 'queued'
            order by created_at
            for update skip locked
            limit 1
         )
        returning id, user_id, job_type, source_item_id, style, hd, quality,
                  credits_reserved
        """
    )


async def _item_fetch_url(
    conn: asyncpg.Connection, user_id: object, item_id: object
) -> str | None:
    """Resolve a wardrobe item's best image (cutout → original) to a FETCHABLE url
    — an R2 object is signed (short TTL), a legacy url passes through. Scoped to
    the owner (§11)."""
    item = str(item_id)
    assets = await resolve_images(conn, "wardrobe_item", [item], ("cutout", "original"))
    hit = assets.get((item, "cutout")) or assets.get((item, "original"))
    if hit and hit.url:
        return hit.url
    return await conn.fetchval(
        "select coalesce(cutout_url, image_url) from public.wardrobe_items "
        "where id = $1::uuid and user_id = $2::uuid",
        item,
        str(user_id),
    )


async def _active_catalog_model(
    conn: asyncpg.Connection, style: str | None
) -> asyncpg.Record | None:
    """An active catalog model preset image for `style` (or any active one as a
    fallback). None when none is configured → the job fails cleanly + refunds."""
    return await conn.fetchrow(
        """
        select id, image_url from public.tryon_model_presets
         where kind = 'catalog' and is_active = true and image_url is not null
           and ($1::text is null or style = $1)
         order by sort_order
         limit 1
        """,
        style,
    )


async def _log_usage(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    provider: str,
    task: str,
    success: bool,
    latency_ms: int,
    images: int = 1,
) -> None:
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, images, estimated_usd, latency_ms, success)
        values ($1::uuid, $2, $3, $4, $5, $6, $7)
        """,
        str(user_id),
        provider,
        task,
        images,
        _PROVIDER_USD.get(provider, Decimal("0")) * images,
        latency_ms,
        success,
    )


async def _fail_and_refund(
    conn: asyncpg.Connection,
    *,
    job: asyncpg.Record,
    error: str,
    provider: str,
    latency_ms: int,
) -> None:
    """An ai_job failed: mark it failed, REFUND the credit reserved at submit (§7,
    idempotent), reset the source item's ai_status, then log the failed usage."""
    job_id, user_id = job["id"], job["user_id"]
    async with conn.transaction():
        await conn.execute(
            "update public.ai_jobs set status = 'failed', error_message = $2, "
            "credits_charged = 0, completed_at = now() where id = $1::uuid",
            str(job_id),
            error[:500],
        )
        if job["job_type"] == "enhance_item" and job["source_item_id"]:
            # Keep the regular background-removed item; just clear the enhancing flag.
            await conn.execute(
                "update public.wardrobe_items set ai_status = 'failed' where id = $1::uuid",
                str(job["source_item_id"]),
            )
        await refund_credit(conn, str(user_id), ref=str(job_id))
    await _log_usage(
        conn,
        user_id=user_id,
        provider=provider,
        task=job["job_type"],
        success=False,
        latency_ms=latency_ms,
    )


async def _store_output(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    role: str,
    image: bytes,
    content_type: str,
) -> tuple[str, object | None]:
    """Persist a generated image into our own storage (R2 when enabled, else the
    private Supabase bucket). Returns (stored_ref, r2_asset_or_None). The stored
    ref is the R2 object_key or the Supabase path; the serve endpoint signs it."""
    if get_settings().r2_writes_enabled:
        asset = await get_storage_provider().put(
            image,
            visibility="private",
            prefix=f"{user_id}/{role}",
            content_type=content_type,
        )
        return asset.object_key, asset
    path = await upload_private_image(
        _GENERATED_BUCKET, str(user_id), role, image, content_type
    )
    return path, None


async def _record_generated(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    job_id: object,
    source_item_id: object | None,
    gen_type: str,
    stored_ref: str,
    r2_asset: object | None,
    content_type: str,
) -> str:
    """Insert the generated_images row + (for R2) its media_assets ledger entry."""
    gen_id = await conn.fetchval(
        """
        insert into public.generated_images
          (user_id, source_item_id, job_id, type, output_url, is_ai_generated)
        values ($1::uuid, $2, $3::uuid, $4, $5, true)
        returning id
        """,
        str(user_id),
        str(source_item_id) if source_item_id else None,
        str(job_id),
        gen_type,
        stored_ref,
    )
    if r2_asset is not None:
        await insert_asset(
            conn,
            owner_kind="generated_image",
            owner_id=gen_id,
            role=gen_type,
            user_id=user_id,
            visibility="private",
            storage_provider="r2",
            object_key=r2_asset.object_key,
            thumbnail_key=getattr(r2_asset, "thumbnail_key", None),
            content_hash=getattr(r2_asset, "content_hash", None),
            mime_type=content_type,
        )
    return gen_id


async def _process_enhance(
    conn: asyncpg.Connection, job: asyncpg.Record
) -> tuple[str, object, str]:
    """Run AI Enhance on the item's cutout. Raises ImageGenError on failure (the
    caller refunds). Returns (stored_ref, r2_asset_or_None, content_type)."""
    item_id = job["source_item_id"]
    if not item_id:
        raise ImageGenError("No source item for enhance.")
    fetch_url = await _item_fetch_url(conn, job["user_id"], item_id)
    if not fetch_url:
        raise ImageGenError("Item image not found.")
    original = await download_image(fetch_url)
    enhanced = await get_image_enhancer().enhance(original, content_type="image/png")
    stored_ref, r2_asset = await _store_output(
        conn, user_id=job["user_id"], role="enhanced", image=enhanced,
        content_type="image/png",
    )
    return stored_ref, r2_asset, "image/png"


async def _process_catalog(
    conn: asyncpg.Connection, job: asyncpg.Record
) -> tuple[str, object, str]:
    """Render the item on a catalog model via the try-on provider (FASHN). Raises
    on failure / when no active catalog model is configured (caller refunds)."""
    item_id = job["source_item_id"]
    if not item_id:
        raise TryOnError("No source item for catalog shot.")
    model = await _active_catalog_model(conn, job["style"])
    if model is None or not model["image_url"]:
        raise ImageGenNotConfigured(_CATALOG_UNAVAILABLE)
    garment_url = await _item_fetch_url(conn, job["user_id"], item_id)
    if not garment_url:
        raise TryOnError("Item image not found.")
    result_url = await get_tryon_provider().generate(
        person_image_url=model["image_url"], garment_image_url=garment_url
    )
    content_type = (
        "image/png" if result_url.split("?")[0].lower().endswith(".png") else "image/jpeg"
    )
    image = await download_image(result_url)
    stored_ref, r2_asset = await _store_output(
        conn, user_id=job["user_id"], role="catalog", image=image,
        content_type=content_type,
    )
    return stored_ref, r2_asset, content_type


async def process_ai_job(conn: asyncpg.Connection, job: asyncpg.Record) -> None:
    job_id, user_id, job_type = job["id"], job["user_id"], job["job_type"]
    provider = get_tryon_provider().name if job_type == "catalog_model" else "stub"
    started = time.monotonic()

    try:
        if job_type == "enhance_item":
            stored_ref, r2_asset, content_type = await _process_enhance(conn, job)
            gen_type = "enhanced_item"
        elif job_type == "catalog_model":
            stored_ref, r2_asset, content_type = await _process_catalog(conn, job)
            gen_type = "catalog_model"
        else:
            # tryon_* values are reserved for tryon_jobs; never queued here.
            raise ImageGenError(f"Unsupported ai_job type: {job_type}")
    except (ImageGenError, TryOnError) as exc:
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn, job=job, error=str(exc), provider=provider, latency_ms=latency
        )
        log.warning("ai_job %s (%s) failed, refunded: %s", job_id, job_type, exc)
        return
    except Exception as exc:  # unexpected → fail + refund (never charge on failure)
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn,
            job=job,
            error="We couldn't finish that. Please try again — your credit was refunded.",
            provider=provider,
            latency_ms=latency,
        )
        log.warning("ai_job %s (%s) errored, refunded: %s", job_id, job_type, exc)
        return

    latency = int((time.monotonic() - started) * 1000)

    # Persist the output + mark completed atomically. Credits stay reserved at
    # submit; success simply keeps them (credits_charged = credits_reserved).
    async with conn.transaction():
        await _record_generated(
            conn,
            user_id=user_id,
            job_id=job_id,
            source_item_id=job["source_item_id"],
            gen_type=gen_type,
            stored_ref=stored_ref,
            r2_asset=r2_asset,
            content_type=content_type,
        )
        if job_type == "enhance_item" and job["source_item_id"]:
            # The enhanced image becomes the item's cover (does not touch original).
            await conn.execute(
                """
                update public.wardrobe_items
                   set enhanced_image_url = $2, cover_image_url = $2,
                       ai_enhanced = true, ai_status = 'done'
                 where id = $1::uuid
                """,
                str(job["source_item_id"]),
                stored_ref,
            )
        await conn.execute(
            """
            update public.ai_jobs
               set status = 'completed', error_message = null, provider = $2,
                   output_urls = array[$3], credits_charged = credits_reserved,
                   completed_at = now()
             where id = $1::uuid
            """,
            str(job_id),
            provider,
            stored_ref,
        )

    await _log_usage(
        conn, user_id=user_id, provider=provider, task=job_type, success=True,
        latency_ms=latency,
    )
    log.info("ai_job %s (%s) completed", job_id, job_type)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued ai_job. Returns True if one was processed."""
    job = await claim_next_ai_job(conn)
    if job is None:
        return False
    await process_ai_job(conn, job)
    return True
