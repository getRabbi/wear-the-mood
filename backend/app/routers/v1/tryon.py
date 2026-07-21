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

from app.core.credits import (
    InsufficientCreditsError,
    authorize_tryon,
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
from app.models.common import ErrorCode
from app.models.tryon import TryOnJobResponse, TryOnRequest, TryOnResultItem
from app.queues import KIND_TRYON, enqueue_signal
from app.services.billing import user_plan
from app.services.media.refresh import freshen_all, freshen_media_url
from app.services.media.repo import resolve_images
from app.services.moderation import get_moderator
from app.services.moderation.base import ModerationInputError, ModerationUnavailable
from app.services.storage import create_signed_url
from app.services.tryon import get_tryon_provider

_RESULTS_BUCKET = "tryon-results"


async def _display_url(stored: str | None) -> str | None:
    """A stored result is either our private Supabase PATH (legacy) or a provider
    URL (pre-persistence). Sign the former; pass the latter through."""
    if not stored:
        return None
    if stored.startswith("http"):
        return stored
    try:
        return await create_signed_url(_RESULTS_BUCKET, stored)
    except Exception:  # don't let a transient signing error 500 the whole list
        return None


async def _resolve_result(
    conn: asyncpg.Connection, result_id: object | None, stored: str | None
) -> str | None:
    """Resolve a try-on result image: media_assets (R2 signed) first, else the
    legacy Supabase column path. Per-record, so R2 + legacy coexist (point A)."""
    if result_id is not None:
        assets = await resolve_images(conn, "tryon_result", [result_id], ("result",))
        hit = assets.get((str(result_id), "result"))
        if hit and hit.url:
            return hit.url
    return await _display_url(stored)


router = APIRouter(tags=["tryon"])

log = logging.getLogger("fashionos.tryon")

_ENDPOINT = "POST /v1/tryon"


# A DISTINCT, actionable message per input kind (§13): the user must know whether
# it was their BODY photo or the chosen GARMENT that couldn't be loaded, so they
# fix the right one instead of blindly retrying the same broken source.
_UNREADABLE_MSG = {
    "body": "We couldn't load your body photo. Please re-select your try-on photo and try again.",
    "garment": "We couldn't load the selected garment. Please re-add it from your closet and try again.",
}


async def _moderate_one(user_id: str, url: str, *, kind: str) -> None:
    """Moderate ONE input (§19), raising a kind-specific typed error so the app can
    tell the user which image failed. Runs outside the DB transaction (network)."""
    moderator = get_moderator()
    try:
        result = await moderator.check_image(url)
    except ModerationInputError as exc:
        # The URL is unusable (unfetchable / expired / wrong type). Client error ->
        # typed VALIDATION_ERROR, never an unhandled 500 (§13). URLs are re-signed
        # fresh just before this, so an unreadable input is a genuinely bad source.
        log.warning("try-on %s input rejected for user %s: %s", kind, user_id, exc)
        raise ApiError(ErrorCode.VALIDATION_ERROR, _UNREADABLE_MSG[kind], 422) from exc
    except ModerationUnavailable as exc:
        # Fail CLOSED: §19 makes input moderation mandatory, so an unavailable
        # moderator must block the job rather than let it through unchecked.
        log.error("moderation unavailable for user %s: %s", user_id, exc)
        raise ApiError(
            ErrorCode.PROVIDER_ERROR,
            "Can't check this image right now. Please try again shortly.",
            503,
        ) from exc
    if not result.allowed:
        log.warning("try-on %s input blocked for user %s (%s)", kind, user_id, result.reason)
        raise ApiError(ErrorCode.MODERATION_BLOCKED, "This image can't be used for try-on.", 422)


async def _resolve_person_image(conn: asyncpg.Connection, plan: object, body: TryOnRequest) -> str:
    """Resolve the try-on BODY (Try-On Body System, BUILD_PROMPT_PRO_PROMAX.md).

    * own_photo    — the client-sent person image (the user's saved body photo) —
                     unchanged.
    * studio_model — server-resolves the chosen preset's image (authoritative,
                     not the client URL). PER-MODEL gating: a preset flagged
                     is_pro_only requires Pro/Pro Max; the free base models
                     (a female + a male) are usable by anyone.
    * user_avatar  — My Style Model: FUTURE-READY only, rejected for now.
    """
    if body.model_source == "studio_model":
        row = await conn.fetchrow(
            "select image_url, is_pro_only from public.tryon_model_presets "
            "where id = $1::uuid and kind = 'studio_tryon' and is_active = true "
            "  and image_url is not null",
            str(body.preset_model_id),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "That studio model isn't available.", 404)
        if row["is_pro_only"] and plan.tier == "free":  # type: ignore[attr-defined]
            raise ApiError(ErrorCode.PAYWALL, "This studio model is a Pro feature.", 402)
        return row["image_url"]
    if body.model_source == "user_avatar":
        raise ApiError(ErrorCode.VALIDATION_ERROR, "My Style Model isn't available yet.", 422)
    return body.person_image_url


async def _resolve_garment_stack(
    conn: asyncpg.Connection, user_id: str, body: TryOnRequest
) -> list[str]:
    """The garment source is one of: the full stack (garment_image_urls, in
    render order), a single URL, or one of the user's own wardrobe items (looked
    up scoped by user_id, §11). Returns the ordered stack (length >= 1)."""
    if body.garment_image_urls:
        return list(body.garment_image_urls)
    if body.garment_image_url:
        return [body.garment_image_url]
    # Resolve the owned item's garment to a FETCHABLE url the provider can pull:
    # an R2 cutout/original is stored as an object_key, so sign it (the short TTL
    # comfortably covers the worker→FASHN fetch); a legacy item is already a url.
    item_id = str(body.wardrobe_item_id)
    assets = await resolve_images(conn, "wardrobe_item", [item_id], ("cutout", "original"))
    hit = assets.get((item_id, "cutout")) or assets.get((item_id, "original"))
    if hit and hit.url:
        return [hit.url]
    url = await conn.fetchval(
        """
        select coalesce(cutout_url, image_url)
          from public.wardrobe_items
         where id = $1::uuid and user_id = $2::uuid
        """,
        item_id,
        user_id,
    )
    if not url:
        raise ApiError(ErrorCode.NOT_FOUND, "Wardrobe item not found.", 404)
    return [url]


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

        # Kill-switch (§14): an admin can disable AI try-on instantly via the
        # `ai_tryon_enabled` flag to halt FASHN spend on a cost runaway. The free
        # 2D preview is client-side, so it stays available.
        if not await flag_enabled(conn, "ai_tryon_enabled", default=True):
            raise ApiError(
                ErrorCode.PROVIDER_ERROR,
                "AI try-on is temporarily unavailable. Try the free 2D preview.",
                503,
            )

        # Server is the only authority on cost + eligibility (§18). HD / Try-On Max
        # is a PRO MAX–ONLY feature (plan.hd_allowed; Pro is false) and costs 4
        # credits; standard costs 1. authorize_tryon rejects (HD_LOCKED / PAYWALL)
        # BEFORE any provider call (§7). The actual credits are RESERVED atomically
        # below when the job is created, and refunded by the worker if it fails.
        plan = await user_plan(conn, user.id)
        state = await get_credits(conn, user.id)
        cost = authorize_tryon(hd=body.hd, plan=plan, state=state)

        # Resolve the BODY (own photo / studio model). studio_model is server-
        # resolved + Pro/Pro Max gated; user_avatar is rejected (future-ready).
        person_image_url = await _resolve_person_image(conn, plan, body)
        garment_stack = await _resolve_garment_stack(conn, user.id, body)

    # RE-SIGN first-party expiring URLs to FRESH ones (root-cause fix): the app may
    # submit a signed URL minted when it loaded the closet/gallery an hour ago and
    # now expired, which moderation (and later FASHN) can't download. Freshening
    # from the same object key/path makes the URL valid again; public/third-party
    # URLs pass through untouched (§8). These freshened URLs are what we moderate
    # AND store on the job, so the worker inherits fresh sources too.
    person_image_url = await freshen_media_url(person_image_url)
    garment_stack = await freshen_all(garment_stack)

    # Moderate inputs before the job is created (§19) — kept out of the DB
    # transaction because it's a network call. A curated studio model is trusted,
    # so only the user's OWN photo is moderated; garments always are. Each input is
    # moderated separately so a failure names the BODY vs the GARMENT (§13).
    if body.model_source == "own_photo":
        await _moderate_one(user.id, person_image_url, kind="body")
    for garment_url in garment_stack:
        await _moderate_one(user.id, garment_url, kind="garment")

    async with get_pool().acquire() as conn:
        # Reserve + create + store atomically: any failure below rolls back the
        # reservation, freeing the key for a clean retry.
        async with conn.transaction():
            if not await reserve_key(conn, idempotency_key, user.id, _ENDPOINT):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)

            provider = get_tryon_provider()
            # garment_image_url stays the PRIMARY (first) garment for backward
            # compatibility; garment_image_urls carries the full ordered stack.
            job_id = await conn.fetchval(
                """
                insert into public.tryon_jobs
                  (user_id, status, person_image_url, garment_image_url,
                   garment_image_urls, wardrobe_item_id, provider, idempotency_key,
                   hd, model_source, preset_model_id)
                values ($1::uuid, 'queued', $2, $3, $4::text[], $5, $6, $7, $8,
                        $9, $10)
                returning id
                """,
                user.id,
                person_image_url,
                garment_stack[0],
                garment_stack,
                str(body.wardrobe_item_id) if body.wardrobe_item_id else None,
                provider.name,
                idempotency_key,
                body.hd,
                body.model_source,
                str(body.preset_model_id) if body.preset_model_id else None,
            )

            # RESERVE the credits now, under a row lock, inside the same
            # transaction that created the job (§7/§12): two concurrent submits can
            # never both pass and the balance can never go negative. A job that
            # ultimately fails is refunded by the worker. If credits raced away
            # between the pre-check and here, this rolls the whole job back.
            try:
                await spend_credit(conn, str(user.id), cost=cost, ref=str(job_id))
            except InsufficientCreditsError:
                message = (
                    f"You need {cost} credits for HD."
                    if body.hd
                    else "You're out of AI credits. Upgrade or top up to keep generating."
                )
                raise ApiError(ErrorCode.PAYWALL, message, 402) from None

            response = {"job_id": str(job_id), "status": "queued", "state": "queued"}
            await store_response(conn, idempotency_key, user.id, _ENDPOINT, 202, response)

    # Wake the orchestrator AFTER the commit, outside any transaction (§11.5). Best-
    # effort: a failed signal leaves the job 'queued' for the 5-min recovery task, and
    # the DO bridge polls the DB (ignoring the stub queue), so this is harmless there.
    if await enqueue_signal(KIND_TRYON, str(job_id)):
        async with get_pool().acquire() as conn:
            await conn.execute(
                "update public.tryon_jobs set last_signal_at = now() where id = $1::uuid",
                str(job_id),
            )
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
        # Batch-resolve the page: media_assets (R2) where present, legacy path otherwise.
        assets = await resolve_images(conn, "tryon_result", [r["id"] for r in rows], ("result",))
        items: list[TryOnResultItem] = []
        for r in rows:
            hit = assets.get((str(r["id"]), "result"))
            url = hit.url if (hit and hit.url) else await _display_url(r["result_image_url"])
            items.append(
                TryOnResultItem(id=str(r["id"]), result_image_url=url, created_at=r["created_at"])
            )
    return items


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

        result_image_url: str | None = None
        if job["status"] == "done":
            res = await conn.fetchrow(
                """
                select id, result_image_url
                  from public.tryon_results
                 where job_id = $1::uuid and user_id = $2::uuid
                 order by created_at desc
                 limit 1
                """,
                str(job_id),
                user.id,
            )
            if res is not None:
                result_image_url = await _resolve_result(conn, res["id"], res["result_image_url"])

    return TryOnJobResponse(
        job_id=str(job["id"]),
        status=job["status"],
        result_image_url=result_image_url,
        error=job["error"],
    )
