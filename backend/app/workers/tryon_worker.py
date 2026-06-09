"""Try-on job draining (Render worker, CLAUDE.md §7).

Claims queued `tryon_jobs` one at a time (FOR UPDATE SKIP LOCKED so multiple
workers never grab the same row), runs the TryOnProvider, writes a result and
marks the job done — charging the credit ONLY on success (§7). Provider failures
mark the job failed and never charge. Every attempt is logged to ai_usage_log
(§14).
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

import asyncpg

from app.core.credits import InsufficientCreditsError, spend_credit
from app.services.tryon import get_tryon_provider

log = logging.getLogger("fashionos.worker.tryon")

# Stub provider is free; FASHN is ~$0.075/image (§2.2) — fill in when wired.
_PROVIDER_USD: dict[str, Decimal] = {"stub": Decimal("0")}


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
        returning id, user_id, person_image_url, garment_image_url, provider
        """
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
        values ($1::uuid, $2, 'tryon', 1, $3, $4, $5)
        """,
        str(user_id),
        provider,
        _PROVIDER_USD.get(provider, Decimal("0")),
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

    try:
        result_url = await provider.generate(
            person_image_url=job["person_image_url"],
            garment_image_url=job["garment_image_url"],
        )
    except Exception as exc:  # provider/timeout error -> fail, never charge (§7)
        latency = int((time.monotonic() - started) * 1000)
        await _mark_failed(conn, job_id, str(exc))
        await _log_usage(
            conn, user_id=user_id, provider=provider.name, success=False, latency_ms=latency
        )
        log.warning("try-on job %s failed: %s", job_id, exc)
        return

    latency = int((time.monotonic() - started) * 1000)
    try:
        # Charge + persist result + mark done atomically (success only, §7).
        async with conn.transaction():
            await spend_credit(conn, str(user_id))
            await conn.execute(
                """
                insert into public.tryon_results (job_id, user_id, result_image_url)
                values ($1::uuid, $2::uuid, $3)
                """,
                str(job_id),
                str(user_id),
                result_url,
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
            conn, user_id=user_id, provider=provider.name, success=False, latency_ms=latency
        )
        log.warning("try-on job %s done but no credits to charge", job_id)
        return

    await _log_usage(
        conn, user_id=user_id, provider=provider.name, success=True, latency_ms=latency
    )
    log.info("try-on job %s done", job_id)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued job. Returns True if one was processed."""
    job = await claim_next_job(conn)
    if job is None:
        return False
    await process_job(conn, job)
    return True
