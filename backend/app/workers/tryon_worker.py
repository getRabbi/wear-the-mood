"""Try-on job draining (Render worker, CLAUDE.md §7).

Claims queued `tryon_jobs` one at a time (FOR UPDATE SKIP LOCKED so multiple
workers never grab the same row), runs the TryOnProvider, writes a result and
marks the job done — charging the credit ONLY on success (§7). Provider failures
mark the job failed and never charge. Every attempt is logged to ai_usage_log
(§14).
"""

from __future__ import annotations

import asyncio
import logging
import time
from base64 import b64encode
from decimal import Decimal

import asyncpg

from app.core.credits import InsufficientCreditsError, spend_credit
from app.services.billing import is_premium
from app.services.storage import download_image, upload_tryon_result
from app.services.tryon import get_tryon_provider
from app.services.tryon.base import TryOnInputError, TryOnProvider, TryOnTransientError

log = logging.getLogger("fashionos.worker.tryon")

# Stub provider is free; FASHN is ~$0.075/image (§2.2).
_PROVIDER_USD: dict[str, Decimal] = {"stub": Decimal("0"), "fashn": Decimal("0.075")}

# Retry transient provider failures (network blip, 5xx/overload, generic terminal
# failure) with exponential backoff — these are the intermittent "works on retry"
# cases (CLAUDE.md §7). Permanent input errors are NOT retried. Kept small so the
# total stays within the app's poll ceiling for the common (fast-failing) case.
_MAX_ATTEMPTS = 3
_BACKOFF_BASE = 2.0  # seconds: 2s, 4s between attempts (patched to 0 in tests)

# Generic, user-safe message when transient retries are exhausted (the raw
# error is logged for diagnosis but never shown — §13/§14).
_RETRY_EXHAUSTED_MSG = "We couldn't generate your try-on. Please try again in a moment."


async def _generate_with_retry(
    provider: TryOnProvider,
    *,
    person_image_url: str,
    garment_image_url: str,
    job_id: object,
) -> str:
    """Run one garment render, retrying transient failures with backoff. Permanent
    input errors (and our own timeout) propagate immediately — retrying won't help."""
    last: TryOnTransientError | None = None
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        try:
            return await provider.generate(
                person_image_url=person_image_url,
                garment_image_url=garment_image_url,
            )
        except TryOnTransientError as exc:
            last = exc
            log.warning(
                "try-on job %s attempt %d/%d transient failure: %s",
                job_id, attempt, _MAX_ATTEMPTS, exc,
            )
            if attempt < _MAX_ATTEMPTS:
                await asyncio.sleep(_BACKOFF_BASE * (2 ** (attempt - 1)))
    assert last is not None  # loop only exits via return or after setting `last`
    raise last


async def _inline_person_image(url: str) -> str:
    """Return the user's try-on photo as a base64 data URI so the provider renders
    from inline bytes instead of fetching a URL itself (CLAUDE.md §8, §11).

    ROOT CAUSE of "couldn't finish try-on": the photo lives in the PRIVATE
    `avatars` bucket and reaches us as a short-lived **signed** URL. Handing that
    straight to FASHN means FASHN's servers must fetch it on their own timeline —
    if it has expired (1h TTL) or the bucket rejects the request, the prediction
    stalls until our poll ceiling and surfaces as a timeout. Inlining the bytes
    removes that dependency entirely and keeps the bucket private. A genuinely
    unreadable photo now fails FAST with a clear, actionable message instead of a
    silent timeout. Public garment URLs and chained provider outputs are passed
    through unchanged — those are already fetchable."""
    try:
        image = await download_image(url)
    except Exception as exc:
        raise TryOnInputError(
            "We couldn't load your try-on photo. Please re-select your photo and try again."
        ) from exc
    ctype = "image/png" if url.split("?")[0].lower().endswith(".png") else "image/jpeg"
    return f"data:{ctype};base64,{b64encode(image).decode('ascii')}"


async def claim_next_job(conn: asyncpg.Connection) -> asyncpg.Record | None:
    """Atomically claim the oldest queued job, flipping it to 'processing'."""
    return await conn.fetchrow(
        """
        update public.tryon_jobs
           set status = 'processing'
         where id = (
           select id
             from public.tryon_jobs
            where status = 'queued'
            order by created_at
            for update skip locked
            limit 1
         )
        returning id, user_id, person_image_url, garment_image_url,
                  garment_image_urls, provider
        """
    )


async def _log_usage(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    provider: str,
    success: bool,
    latency_ms: int,
    images: int = 1,
) -> None:
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, images, estimated_usd, latency_ms, success)
        values ($1::uuid, $2, 'tryon', $3, $4, $5, $6)
        """,
        str(user_id),
        provider,
        images,
        _PROVIDER_USD.get(provider, Decimal("0")) * images,
        latency_ms,
        success,
    )


async def _mark_failed(conn: asyncpg.Connection, job_id: object, error: str) -> None:
    await conn.execute(
        "update public.tryon_jobs set status = 'failed', error = $2 where id = $1::uuid",
        str(job_id),
        error[:500],
    )


async def process_job(conn: asyncpg.Connection, job: asyncpg.Record) -> None:
    job_id, user_id = job["id"], job["user_id"]
    provider = get_tryon_provider()
    started = time.monotonic()

    # The full outfit stack in render order; falls back to the single primary
    # garment for legacy jobs.
    stack: list[str] = list(job["garment_image_urls"] or []) or [
        job["garment_image_url"]
    ]

    try:
        # Hand the provider the user's photo as inline base64 (not the private,
        # expiring signed URL) so it never has to fetch it — see
        # _inline_person_image for the full root-cause note.
        log.info("processing try-on job %s (%d garment(s))", job_id, len(stack))
        current = await _inline_person_image(job["person_image_url"])
        # MULTI-GARMENT STRATEGY: the provider (FASHN) renders ONE garment at a
        # time, so we CHAIN — each render's output becomes the next render's
        # person image, applied in the client-provided render order
        # (dress/base → top → bottom → outerwear → shoes/bag/accessory). One AI
        # job = one generated look (charged once, below), regardless of count.
        result_url = job["person_image_url"]  # fallback only if the stack is empty
        for garment in stack:
            result_url = await _generate_with_retry(
                provider,
                person_image_url=current,
                garment_image_url=garment,
                job_id=job_id,
            )
            current = result_url
    except TryOnInputError as exc:
        # Permanent + user-actionable (bad pose, NSFW, unreadable photo): show the
        # specific guidance so the user can fix it. Never charge (§7).
        latency = int((time.monotonic() - started) * 1000)
        await _mark_failed(conn, job_id, str(exc))
        await _log_usage(
            conn,
            user_id=user_id,
            provider=provider.name,
            success=False,
            latency_ms=latency,
            images=len(stack),
        )
        log.warning("try-on job %s failed (input): %s", job_id, exc)
        return
    except Exception as exc:  # transient exhausted / timeout / unexpected -> fail
        # Retries are spent (or it timed out) — surface a clean generic message;
        # the raw error is logged for diagnosis. Never charge on failure (§7).
        latency = int((time.monotonic() - started) * 1000)
        await _mark_failed(conn, job_id, _RETRY_EXHAUSTED_MSG)
        await _log_usage(
            conn,
            user_id=user_id,
            provider=provider.name,
            success=False,
            latency_ms=latency,
            images=len(stack),
        )
        log.warning("try-on job %s failed after retries: %s", job_id, exc)
        return

    latency = int((time.monotonic() - started) * 1000)

    # Persist the result into our own storage so the user's history survives the
    # provider's short output retention (§8). Best-effort: if it fails we keep the
    # provider URL so the run still delivers a result.
    stored_result = result_url
    try:
        content_type = (
            "image/png"
            if result_url.split("?")[0].lower().endswith(".png")
            else "image/jpeg"
        )
        image = await download_image(result_url)
        stored_result = await upload_tryon_result(str(user_id), image, content_type)
    except Exception as exc:
        log.warning(
            "persisting try-on result for job %s failed; keeping provider URL: %s",
            job_id,
            exc,
        )

    try:
        # Charge + persist result + mark done atomically (success only, §7).
        # Premium users aren't charged a credit — their subscription covers AI
        # try-ons (§18); only credited free users are debited.
        async with conn.transaction():
            if not await is_premium(conn, str(user_id)):
                await spend_credit(conn, str(user_id))
            await conn.execute(
                """
                insert into public.tryon_results (job_id, user_id, result_image_url)
                values ($1::uuid, $2::uuid, $3)
                """,
                str(job_id),
                str(user_id),
                stored_result,
            )
            await conn.execute(
                "update public.tryon_jobs set status = 'done', error = null where id = $1::uuid",
                str(job_id),
            )
    except InsufficientCreditsError:
        # Raced out of credits between the POST gate and completion — don't
        # deliver a result we can't charge for.
        await _mark_failed(conn, job_id, "insufficient_credits")
        await _log_usage(
            conn,
            user_id=user_id,
            provider=provider.name,
            success=False,
            latency_ms=latency,
            images=len(stack),
        )
        log.warning("try-on job %s done but no credits to charge", job_id)
        return

    await _log_usage(
        conn,
        user_id=user_id,
        provider=provider.name,
        success=True,
        latency_ms=latency,
        images=len(stack),
    )
    log.info("try-on job %s done", job_id)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued job. Returns True if one was processed."""
    job = await claim_next_job(conn)
    if job is None:
        return False
    await process_job(conn, job)
    return True
