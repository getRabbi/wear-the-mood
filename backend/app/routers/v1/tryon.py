"""Async try-on endpoints (CLAUDE.md §7).

POST creates a queued `tryon_jobs` row and returns 202 + {job_id}; the Render
worker (next step) polls for status='queued', calls the TryOnProvider, writes a
result and flips status to done|failed, charging the credit ONLY on success.
GET returns the job's current status (and result URL once done).
"""

from __future__ import annotations

import logging
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from app.core.credits import InsufficientCreditsError, get_credits, has_credit
from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.idempotency import (
    get_stored_response,
    require_idempotency_key,
    reserve_key,
    store_response,
)
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.tryon import TryOnJobResponse, TryOnRequest, TryOnResultItem
from app.services.billing import is_premium
from app.services.moderation import get_moderator
from app.services.storage import create_signed_url
from app.services.tryon import get_tryon_provider

_RESULTS_BUCKET = "tryon-results"


async def _display_url(stored: str | None) -> str | None:
    """A stored result is either our private storage PATH (new) or a legacy
    provider URL (pre-persistence). Sign the former; pass the latter through."""
    if not stored:
        return None
    if stored.startswith("http"):
        return stored
    try:
        return await create_signed_url(_RESULTS_BUCKET, stored)
    except Exception:  # don't let a transient signing error 500 the whole list
        return None

router = APIRouter(tags=["tryon"])

log = logging.getLogger("fashionos.tryon")

_ENDPOINT = "POST /v1/tryon"


async def _moderate_inputs(user_id: str, *image_urls: str) -> None:
    """Reject abusive try-on inputs before any job is created (§19). Runs outside
    the DB transaction (it's a network call). Decisions are logged."""
    moderator = get_moderator()
    for url in image_urls:
        result = await moderator.check_image(url)
        if not result.allowed:
            log.warning("try-on input blocked for user %s (%s)", user_id, result.reason)
            raise ApiError(
                ErrorCode.MODERATION_BLOCKED,
                "This image can't be used for try-on.",
                422,
            )


async def _resolve_garment_url(conn: asyncpg.Connection, user_id: str, body: TryOnRequest) -> str:
    """The garment is either a supplied URL or one of the user's own wardrobe
    items (looked up scoped by user_id, §11)."""
    if body.garment_image_url:
        return body.garment_image_url
    url = await conn.fetchval(
        """
        select coalesce(cutout_url, image_url)
          from public.wardrobe_items
         where id = $1::uuid and user_id = $2::uuid
        """,
        str(body.wardrobe_item_id),
        user_id,
    )
    if not url:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    return url


@router.post("/tryon", status_code=202, response_model=TryOnJobResponse)
async def create_tryon(
    body: TryOnRequest,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    async with get_pool().acquire() as conn:
        # Replay a completed identical request (§9) — no re-charge, no re-enqueue.
        stored = await get_stored_response(conn, idempotency_key, user.id, _ENDPOINT)
        if stored is not None:
            return JSONResponse(status_code=stored.status_code, content=stored.response)

        # Gate BEFORE reserving the key so a user who tops up can retry the same
        # action. Premium users run AI even without a daily free credit (§18);
        # credited free users pass here and are charged on success only (§7).
        if not await is_premium(conn, user.id) and not has_credit(
            await get_credits(conn, user.id)
        ):
            raise InsufficientCreditsError()

        garment_url = await _resolve_garment_url(conn, user.id, body)

    # Moderate inputs before the job is created (§19) — kept out of the DB
    # transaction because it's a network call.
    await _moderate_inputs(user.id, body.person_image_url, garment_url)

    async with get_pool().acquire() as conn:
        # Reserve + create + store atomically: any failure below rolls back the
        # reservation, freeing the key for a clean retry.
        async with conn.transaction():
            if not await reserve_key(conn, idempotency_key, user.id, _ENDPOINT):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)

            provider = get_tryon_provider()
            job_id = await conn.fetchval(
                """
                insert into public.tryon_jobs
                  (user_id, status, person_image_url, garment_image_url,
                   wardrobe_item_id, provider, idempotency_key)
                values ($1::uuid, 'queued', $2, $3, $4, $5, $6)
                returning id
                """,
                user.id,
                body.person_image_url,
                garment_url,
                str(body.wardrobe_item_id) if body.wardrobe_item_id else None,
                provider.name,
                idempotency_key,
            )

            response = {"job_id": str(job_id), "status": "queued"}
            await store_response(conn, idempotency_key, user.id, _ENDPOINT, 202, response)

    # The worker picks the job up via status='queued'.
    return JSONResponse(status_code=202, content=response)


@router.get("/tryon/results", response_model=list[TryOnResultItem])
async def list_tryon_results(
    user: CurrentUser = Depends(get_current_user),
) -> list[TryOnResultItem]:
    """The user's saved try-on results, newest first — powers the history view."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select id, result_image_url, created_at
              from public.tryon_results
             where user_id = $1::uuid
             order by created_at desc
             limit 100
            """,
            user.id,
        )
    return [
        TryOnResultItem(
            id=str(r["id"]),
            result_image_url=await _display_url(r["result_image_url"]),
            created_at=r["created_at"],
        )
        for r in rows
    ]


@router.get("/tryon/{job_id}", response_model=TryOnJobResponse)
async def get_tryon(
    job_id: UUID, user: CurrentUser = Depends(get_current_user)
) -> TryOnJobResponse:
    async with get_pool().acquire() as conn:
        job = await conn.fetchrow(
            """
            select id, status, error
              from public.tryon_jobs
             where id = $1::uuid and user_id = $2::uuid
            """,
            str(job_id),
            user.id,
        )
        if job is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Job not found.", 404)

        result_url: str | None = None
        if job["status"] == "done":
            result_url = await conn.fetchval(
                """
                select result_image_url
                  from public.tryon_results
                 where job_id = $1::uuid and user_id = $2::uuid
                 order by created_at desc
                 limit 1
                """,
                str(job_id),
                user.id,
            )

    return TryOnJobResponse(
        job_id=str(job["id"]),
        status=job["status"],
        result_image_url=await _display_url(result_url),
        error=job["error"],
    )
