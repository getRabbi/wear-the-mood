"""AI Studio endpoints (BUILD_PROMPT_PRO_PROMAX.md).

Premium, credit-gated AI features on the shared `ai_jobs` pipeline:
  * POST /v1/ai/enhance        — AI Enhance an owned closet item (async).
  * POST /v1/ai/catalog-model  — Catalog Model Shot of an owned item (async).
  * GET  /v1/ai/jobs/{job_id}  — poll a job's status + (signed) output.
  * GET  /v1/ai/generated      — the user's AI Looks (saved outputs).
  * DELETE /v1/ai/generated/{id} + POST .../report — manage an output.
  * GET  /v1/studio/models     — active studio models for the try-on body picker.

Every paid action: auth → entitlement (Pro/Pro Max) → credits → RESERVE at submit
(idempotent on the job id) → worker runs the provider → success keeps the credit,
failure refunds it. The credit + provider logic mirrors POST /v1/tryon (§7/§18);
provider secrets stay backend-only (§11).
"""

from __future__ import annotations

import logging
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response
from fastapi.responses import JSONResponse

from app.core.credits import (
    InsufficientCreditsError,
    authorize_premium_ai,
    get_credits,
    spend_credit,
)
from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.flags import flag_enabled
from app.core.idempotency import (
    get_stored_response,
    require_idempotency_key,
    reserve_key,
    store_response,
)
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.ai_studio import (
    CATALOG_STYLES,
    AiJobResponse,
    CatalogModelRequest,
    EnhanceItemRequest,
    GeneratedImageResponse,
    StudioModelPreset,
)
from app.models.common import ErrorCode
from app.queues import KIND_AI, enqueue_signal
from app.services.billing import user_plan
from app.services.media.repo import resolve_private_path

router = APIRouter(tags=["ai-studio"])
log = logging.getLogger("fashionos.ai_studio")

# AI Studio outputs are stored in this private bucket in legacy mode (R2 mode uses
# the private R2 bucket, resolved via media_assets) — matches the worker.
_GENERATED_BUCKET = "tryon-results"


async def _output_url(conn: asyncpg.Connection, stored: str | None) -> str | None:
    """Resolve a stored output ref (R2 object_key or Supabase path) to a viewable
    short-lived URL. An http url passes through; None → None."""
    return await resolve_private_path(conn, stored, _GENERATED_BUCKET)


async def _assert_owns_item(conn: asyncpg.Connection, user_id: str, item_id: UUID) -> None:
    owns = await conn.fetchval(
        "select 1 from public.wardrobe_items where id = $1::uuid and user_id = $2::uuid",
        str(item_id),
        user_id,
    )
    if not owns:
        raise ApiError(ErrorCode.NOT_FOUND, "Item not found.", 404)


async def _create_ai_job(
    *,
    user: CurrentUser,
    idempotency_key: str,
    endpoint: str,
    job_type: str,
    source_item_id: UUID,
    hd: bool,
    style: str | None,
) -> JSONResponse:
    """Shared submit path for enhance_item / catalog_model: entitlement + credit
    gate, then RESERVE + create the job atomically (§7/§9/§18)."""
    async with get_pool().acquire() as conn:
        # Idempotent replay (§9): a repeat key returns the stored 202, no re-charge.
        stored = await get_stored_response(conn, idempotency_key, user.id, endpoint)
        if stored is not None:
            return JSONResponse(status_code=stored.status_code, content=stored.response)

        # Kill-switch (§14): an admin can disable all AI Studio spend instantly.
        if not await flag_enabled(conn, "ai_studio_enabled", default=True):
            raise ApiError(ErrorCode.PROVIDER_ERROR, "AI Studio is temporarily unavailable.", 503)

        await _assert_owns_item(conn, user.id, source_item_id)

        # Server is the only authority on cost + eligibility (§18). Pro/Pro Max only;
        # HD (4 credits) needs hd_allowed. Rejects BEFORE any provider call.
        plan = await user_plan(conn, user.id)
        state = await get_credits(conn, user.id)
        cost = authorize_premium_ai(hd=hd, plan=plan, state=state)

        async with conn.transaction():
            if not await reserve_key(conn, idempotency_key, user.id, endpoint):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)

            job_id = await conn.fetchval(
                """
                insert into public.ai_jobs
                  (user_id, job_type, status, source_item_id, style, hd, quality,
                   credits_reserved, idempotency_key)
                values ($1::uuid, $2, 'queued', $3::uuid, $4, $5, $6, $7, $8)
                returning id
                """,
                user.id,
                job_type,
                str(source_item_id),
                style,
                hd,
                "pro_max" if hd else "standard",
                cost,
                idempotency_key,
            )

            # RESERVE the credits now, under a row lock, in the same transaction —
            # two concurrent submits can never both pass; a failed job is refunded
            # by the worker (§7/§12).
            try:
                await spend_credit(conn, str(user.id), cost=cost, ref=str(job_id))
            except InsufficientCreditsError:
                message = (
                    f"You need {cost} credits for HD."
                    if hd
                    else "You're out of AI credits. Upgrade or top up to keep generating."
                )
                raise ApiError(ErrorCode.PAYWALL, message, 402) from None

            # For enhance, flag the item as enhancing so the closet badge shows
            # immediately; the item keeps displaying its cutout meanwhile.
            if job_type == "enhance_item":
                await conn.execute(
                    "update public.wardrobe_items set ai_status = 'queued' where id = $1::uuid",
                    str(source_item_id),
                )

            response = {"job_id": str(job_id), "status": "queued", "state": "queued"}
            await store_response(conn, idempotency_key, user.id, endpoint, 202, response)

    # Wake the orchestrator after commit (§11.5, best-effort — recovery re-signals).
    if await enqueue_signal(KIND_AI, str(job_id)):
        async with get_pool().acquire() as conn:
            await conn.execute(
                "update public.ai_jobs set last_signal_at = now() where id = $1::uuid",
                str(job_id),
            )
    return JSONResponse(status_code=202, content=response)


@router.post("/ai/enhance", status_code=202, response_model=AiJobResponse)
async def enhance_item(
    body: EnhanceItemRequest,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    """Start an AI Enhance on an owned closet item (Pro/Pro Max, 1 credit)."""
    return await _create_ai_job(
        user=user,
        idempotency_key=idempotency_key,
        endpoint="POST /v1/ai/enhance",
        job_type="enhance_item",
        source_item_id=body.wardrobe_item_id,
        hd=False,
        style=None,
    )


@router.post("/ai/catalog-model", status_code=202, response_model=AiJobResponse)
async def catalog_model(
    body: CatalogModelRequest,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    """Generate a catalog model shot of an owned item (Pro = 1 credit, Pro Max HD =
    4 credits)."""
    style = body.style if body.style in CATALOG_STYLES else "studio"
    return await _create_ai_job(
        user=user,
        idempotency_key=idempotency_key,
        endpoint="POST /v1/ai/catalog-model",
        job_type="catalog_model",
        source_item_id=body.wardrobe_item_id,
        hd=body.hd,
        style=style,
    )


@router.get("/ai/generated", response_model=list[GeneratedImageResponse])
async def list_generated(
    user: CurrentUser = Depends(get_current_user),
) -> list[GeneratedImageResponse]:
    """The user's AI Looks (enhanced items + catalog shots), newest first."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select id, type, output_url, source_item_id, is_ai_generated, created_at
              from public.generated_images
             where user_id = $1::uuid and status = 'active'
             order by created_at desc
             limit 200
            """,
            user.id,
        )
        out: list[GeneratedImageResponse] = []
        for r in rows:
            out.append(
                GeneratedImageResponse(
                    id=str(r["id"]),
                    type=r["type"],
                    output_url=await _output_url(conn, r["output_url"]),
                    source_item_id=str(r["source_item_id"]) if r["source_item_id"] else None,
                    is_ai_generated=r["is_ai_generated"],
                    created_at=r["created_at"],
                )
            )
    return out


@router.delete("/ai/generated/{gen_id}", status_code=204)
async def delete_generated(gen_id: UUID, user: CurrentUser = Depends(get_current_user)) -> Response:
    async with get_pool().acquire() as conn:
        deleted = await conn.fetchval(
            "delete from public.generated_images "
            "where id = $1::uuid and user_id = $2::uuid returning id",
            str(gen_id),
            user.id,
        )
        if deleted is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Image not found.", 404)
    return Response(status_code=204)


@router.post("/ai/generated/{gen_id}/report", status_code=204)
async def report_generated(gen_id: UUID, user: CurrentUser = Depends(get_current_user)) -> Response:
    """Self-report an AI output (safety). Bumps report_count AND files a
    moderation report so the admin queue can actually review it (§19 — a bare
    counter nobody reads is not a safety loop)."""
    async with get_pool().acquire() as conn:
        async with conn.transaction():
            updated = await conn.fetchval(
                "update public.generated_images set report_count = report_count + 1 "
                "where id = $1::uuid and user_id = $2::uuid returning id",
                str(gen_id),
                user.id,
            )
            if updated is None:
                raise ApiError(ErrorCode.NOT_FOUND, "Image not found.", 404)
            await conn.execute(
                "insert into public.reports (reporter_id, subject_type, subject_id, reason) "
                "values ($1::uuid, 'generated_image', $2::uuid, $3)",
                user.id,
                str(gen_id),
                "ai_output_self_report",
            )
    return Response(status_code=204)


@router.get("/ai/jobs/{job_id}", response_model=AiJobResponse)
async def get_ai_job(job_id: UUID, user: CurrentUser = Depends(get_current_user)) -> AiJobResponse:
    async with get_pool().acquire() as conn:
        job = await conn.fetchrow(
            """
            select id, job_type, status, output_urls, error_message
              from public.ai_jobs
             where id = $1::uuid and user_id = $2::uuid
            """,
            str(job_id),
            user.id,
        )
        if job is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Job not found.", 404)
        outputs = list(job["output_urls"] or [])
        output_url = await _output_url(conn, outputs[0]) if outputs else None
    return AiJobResponse(
        job_id=str(job["id"]),
        job_type=job["job_type"],
        status=job["status"],
        output_url=output_url,
        error=job["error_message"],
    )


@router.get("/studio/models", response_model=list[StudioModelPreset])
async def list_studio_models(
    user: CurrentUser = Depends(get_current_user),
) -> list[StudioModelPreset]:
    """Active studio models for the try-on body picker (Pro/Pro Max). Empty until
    the founder uploads real preset images and flips is_active."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select id, name, image_url, style, body_type, skin_tone, pose_type,
                   is_pro_only
              from public.tryon_model_presets
             where kind = 'studio_tryon' and is_active = true and image_url is not null
             order by sort_order
            """
        )
    return [
        StudioModelPreset(
            id=str(r["id"]),
            name=r["name"],
            image_url=r["image_url"],
            style=r["style"],
            body_type=r["body_type"],
            skin_tone=r["skin_tone"],
            pose_type=r["pose_type"],
            is_pro_only=r["is_pro_only"],
        )
        for r in rows
    ]
