"""Async try-on endpoints (CLAUDE.md §7).

POST creates a queued `tryon_jobs` row and returns 202 + {job_id}; the Render
worker (next step) polls for status='queued', calls the TryOnProvider, writes a
result and flips status to done|failed, charging the credit ONLY on success.
GET returns the job's current status (and result URL once done).
"""

from __future__ import annotations

import asyncio
import json
import logging
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, Response
from fastapi.responses import JSONResponse

from app.core.config import get_settings
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
from app.core.monetization import get_policy
from app.core.supabase_auth import CurrentUser, get_current_user
from app.core.timing import StageTimer, current_timer, trace_token
from app.models.common import ErrorCode
from app.models.style_memory import (
    StyleMemoryProfile,
    TryOnFeedback,
    TryOnFeedbackResponse,
)
from app.models.tryon import (
    TryOnJobResponse,
    TryOnRequest,
    TryOnResultItem,
    TryOnSkippedGarment,
    TryOnSource,
)
from app.queues import KIND_TRYON, KIND_WARMUP, enqueue_signal
from app.services import style_memory as sm
from app.services.billing import user_plan
from app.services.media.deletion import delete_content_media
from app.services.media.refresh import freshen_all, freshen_media_url
from app.services.media.repo import resolve_images
from app.services.moderation import get_moderator
from app.services.moderation.base import ModerationInputError, ModerationUnavailable
from app.services.privacy import require_ai_personal_image_consent
from app.services.storage import create_signed_url
from app.services.tryon import get_tryon_provider
from app.services.tryon.planner import LookPlanError, build_plan, skip_message
from app.services.tryon.resolve import GarmentRef, resolve_garments

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
    "garment": "We couldn't load the selected garment. Please re-add it from your closet.",
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


async def _gather_moderation(checks: list) -> None:
    """Await every moderation check, then raise the FIRST failure in input order.

    Deterministic on purpose. `asyncio.gather` without `return_exceptions` raises
    whichever task happens to fail first in wall-clock time, so two bad images
    could produce different messages on two identical requests. Collecting them
    all and re-raising by position means the user is always told about the body
    photo before the garments, and about the first bad garment before the
    second — the same order the serial version reported in.
    """
    results = await asyncio.gather(*checks, return_exceptions=True)
    for result in results:
        if isinstance(result, BaseException):
            raise result


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


async def _resolve_garment_refs(
    conn: asyncpg.Connection, user_id: str, body: TryOnRequest
) -> list[GarmentRef]:
    """The garment source, normalised to references the resolver can identify.

    Four accepted shapes, in descending order of how much the client told us:
    the structured `garments` stack (current clients), a bare URL stack or a
    single URL (already-shipped clients), and an owned wardrobe item id. The
    last three are marked `legacy` because their payload carries no way to say
    what a piece is — that flag is what decides whether an unresolvable garment
    may fall back to the provider's own detector, and it is recorded on the job.
    """
    if body.garments:
        return [
            GarmentRef(
                g.image_url,
                wardrobe_item_id=str(g.wardrobe_item_id) if g.wardrobe_item_id else None,
                product_id=str(g.source_product_id) if g.source_product_id else None,
                category_hint=g.category,
            )
            for g in body.garments
        ]
    if body.garment_image_urls:
        return [GarmentRef(u, legacy=True) for u in body.garment_image_urls]
    if body.garment_image_url:
        return [GarmentRef(body.garment_image_url, legacy=True)]
    # Resolve the owned item's garment to a FETCHABLE url the provider can pull:
    # an R2 cutout/original is stored as an object_key, so sign it (the short TTL
    # comfortably covers the worker→FASHN fetch); a legacy item is already a url.
    item_id = str(body.wardrobe_item_id)
    assets = await resolve_images(conn, "wardrobe_item", [item_id], ("cutout", "original"))
    hit = assets.get((item_id, "cutout")) or assets.get((item_id, "original"))
    if hit and hit.url:
        # The id is known here, so this is NOT a legacy reference: the resolver
        # reads the row and gets a real role.
        return [GarmentRef(hit.url, wardrobe_item_id=item_id)]
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
    return [GarmentRef(url, wardrobe_item_id=item_id)]


async def _resolve_shopping_source(
    conn: asyncpg.Connection, body: TryOnRequest
) -> tuple[str, str, str] | None:
    """The catalog origin of this render, as ``(product_id, merchant_id, kind)``.

    The MERCHANT is looked up from the product rather than taken from the
    request: attribution decides who gets paid, and a client that can name the
    merchant can name the wrong one (§38).

    An id that resolves to nothing is DROPPED, not rejected. A stale or wrong
    source is a broken back-link; refusing the whole request over it would mean
    losing the render instead — a far worse trade for someone who is paying
    credits for it. The result simply reopens as an ordinary look.

    RIGHTS ARE DIFFERENT, and are refused rather than dropped. A withdrawn
    product costs a back-link; a product whose AI image rights are not licensed
    is one whose imagery must not reach the provider at all, and continuing
    without the origin would send exactly that image and merely forget where it
    came from. This is also what makes de-licensing a merchant a real rollback:
    a card cached on a device before the change cannot spend credits rendering a
    product the catalog has since stopped clearing.

    Note the limit of this check, because it is worth stating plainly: it
    catches a request that NAMES the product. A client that sent the same image
    without a `source_product_id` is not matched here — closing that needs
    image-to-product resolution, which does not exist yet.
    """
    if body.source_product_id is None:
        return None
    row = await conn.fetchrow(
        """
        select p.id, p.merchant_id, public.product_tryon_ready(p) as tryon_ready
          from public.products p
         where p.id = $1::uuid
        """,
        str(body.source_product_id),
    )
    if row is None:
        log.info("tryon source product not found; storing job without origin")
        return None
    if not row["tryon_ready"]:
        log.warning("tryon refused: product %s is not try-on ready", body.source_product_id)
        raise ApiError(
            ErrorCode.VALIDATION_ERROR,
            "This product is not available for try-on.",
            400,
        )
    return str(row["id"]), str(row["merchant_id"]), "affiliate_product"


def _source_of(row: asyncpg.Record) -> TryOnSource | None:
    """The source block for a job row, or None for a closet render.

    Keyed on the PRODUCT id, not on `source_kind`: the product reference is
    `on delete set null`, so a withdrawn product leaves the kind behind with
    nothing to point at. That is not a source, and offering to shop it would
    dead-end.
    """
    product_id = row["source_product_id"] if "source_product_id" in row else None
    if product_id is None:
        return None
    merchant_id = row["source_merchant_id"]
    return TryOnSource(
        kind=row["source_kind"] or "affiliate_product",
        product_id=str(product_id),
        merchant_id=str(merchant_id) if merchant_id else None,
        placement=row["source_placement"],
        campaign_id=row["source_campaign_id"],
    )


@router.post("/tryon", status_code=202, response_model=TryOnJobResponse)
async def create_tryon(
    body: TryOnRequest,
    user: CurrentUser = Depends(get_current_user),
    idempotency_key: str = Depends(require_idempotency_key),
) -> JSONResponse:
    # Stage timing only (§14) — no behaviour change. The token is a prefix of the
    # idempotency key, so this line can be lined up against the app's own trace
    # and the worker's without carrying anything replayable.
    timer = StageTimer(scope="tryon.submit", trace=trace_token(idempotency_key))
    token = current_timer.set(timer)
    try:
        return await _create_tryon(body, user, idempotency_key, timer)
    finally:
        timer.emit()
        current_timer.reset(token)


async def _create_tryon(
    body: TryOnRequest,
    user: CurrentUser,
    idempotency_key: str,
    timer: StageTimer,
) -> JSONResponse:
    async with get_pool().acquire() as conn:
        # Replay a completed identical request (§9) — no re-charge, no re-enqueue.
        stored = await get_stored_response(conn, idempotency_key, user.id, _ENDPOINT)
        if stored is not None:
            timer.mark("idempotent_replay")
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
        # The monetization policy resolves the price and the free allowance for
        # THIS user. With every flag off and every config key null (the seeded
        # state) it returns exactly the compiled constants and the deployed
        # setting, so this line is a no-op rewrite of what was here before
        # (spec §53).
        policy = await get_policy(conn, user.id)
        plan = await user_plan(conn, user.id)
        state = await get_credits(conn, user.id, free_limit=policy.free_render_limit)
        cost = authorize_tryon(
            hd=body.hd, plan=plan, state=state, cost=policy.credits.tryon_cost(hd=body.hd)
        )

        # Resolve the BODY (own photo / studio model). studio_model is server-
        # resolved + Pro/Pro Max gated; user_avatar is rejected (future-ready).
        person_image_url = await _resolve_person_image(conn, plan, body)
        refs = await _resolve_garment_refs(conn, user.id, body)
        source = await _resolve_shopping_source(conn, body)

        # THE PLAN (spec Phases 6/7/10). Built here, before anything is charged
        # or sent anywhere, so a conflicting or unrenderable selection costs the
        # user nothing and comes back as a question rather than a bad render.
        strict = await flag_enabled(conn, "tryon_strict_categories", default=False)
        selected = await resolve_garments(conn, user.id, refs, strict=strict)
        try:
            look = build_plan(selected)
        except LookPlanError as exc:
            log.info("tryon plan refused for user %s (%s)", user.id, exc.code)
            raise ApiError(ErrorCode.VALIDATION_ERROR, exc.message, 422) from exc
        garment_stack = look.image_stack()
        timer.mark("resolve_inputs", len(garment_stack))

        # PRIVACY GATE (§10, Apple 5.1.1(i)). `own_photo` is the only body that is
        # the USER's own image; a studio model is our own catalog photograph and
        # carries nobody's personal data, so it is deliberately not gated here —
        # asking permission to share a stock model would be friction that teaches
        # people to dismiss the prompt that matters.
        #
        # Placed BEFORE moderation on purpose. Moderation is itself a third-party
        # transmission of this exact photo (OpenAI), so checking consent only
        # before the FASHN call would leak the image one provider earlier. Nothing
        # has left us at this line, and nothing has been charged.
        consent_version: int | None = None
        if body.model_source == "own_photo":
            consent_version = await require_ai_personal_image_consent(conn, user.id)

    # PRE-WARM the orchestrator (spec Phase 12). Everything that could still
    # refuse this render for a reason we already know — kill switch, plan,
    # credits, consent — has passed, so the worker is going to be needed. It runs
    # scale-to-zero, and production traces put ~25 s between the commit and the
    # container actually running: sending the (work-free) wake signal now
    # overlaps that boot with the freshening + moderation below instead of
    # queueing it after them. Best-effort and idempotent by construction — the
    # worker deletes an empty signal and does nothing.
    if get_settings().tryon_prewarm_enabled:
        await enqueue_signal(KIND_WARMUP, "prewarm")

    # RE-SIGN first-party expiring URLs to FRESH ones (root-cause fix): the app may
    # submit a signed URL minted when it loaded the closet/gallery an hour ago and
    # now expired, which moderation (and later FASHN) can't download. Freshening
    # from the same object key/path makes the URL valid again; public/third-party
    # URLs pass through untouched (§8). These freshened URLs are what we moderate
    # AND store on the job, so the worker inherits fresh sources too.
    person_image_url = await freshen_media_url(person_image_url)
    garment_stack = await freshen_all(garment_stack)
    timer.mark("freshen_urls")

    # Moderate inputs before the job is created (§19) — kept out of the DB
    # transaction because it's a network call. A curated studio model is trusted,
    # so only the user's OWN photo is moderated; garments always are. Each input is
    # moderated separately so a failure still names the BODY vs the GARMENT (§13).
    #
    # RUN CONCURRENTLY (spec Phase 17). These are independent read-only calls to
    # the same provider, and doing them one at a time made a four-piece look wait
    # out five round trips in front of its own 202 — measured at 4.0 s of the
    # 5.8 s submit. `gather` preserves the per-input typed error, so the user is
    # still told exactly which image failed; the first failure wins and the rest
    # are cancelled, which is also what the serial version did.
    checks = [_moderate_one(user.id, url, kind="garment") for url in garment_stack]
    if body.model_source == "own_photo":
        checks.insert(0, _moderate_one(user.id, person_image_url, kind="body"))
    await _gather_moderation(checks)
    timer.mark("moderate_inputs", len(checks))

    async with get_pool().acquire() as conn:
        # Reserve + create + store atomically: any failure below rolls back the
        # reservation, freeing the key for a clean retry.
        async with conn.transaction():
            if not await reserve_key(conn, idempotency_key, user.id, _ENDPOINT):
                raise ApiError(ErrorCode.VALIDATION_ERROR, "Request already in progress.", 409)

            provider = get_tryon_provider()
            # garment_image_url stays the PRIMARY (first) garment for backward
            # compatibility; garment_image_urls carries the full ordered stack —
            # now in the PLAN's order, not tap order, so the worker chains
            # apparel before accessories even if it only reads the array.
            #
            # The plan itself is stored alongside it (0069). That is what makes a
            # Full Look auditable: the row states which pieces were selected,
            # which are meant to be rendered and which were deliberately left
            # out, so "only the shirt came back" is a query rather than a report.
            job_id = await conn.fetchval(
                """
                insert into public.tryon_jobs
                  (user_id, status, person_image_url, garment_image_url,
                   garment_image_urls, wardrobe_item_id, provider, idempotency_key,
                   hd, model_source, preset_model_id,
                   source_kind, source_product_id, source_merchant_id,
                   source_placement, source_campaign_id, consent_version,
                   plan, selected_item_keys, planned_item_keys, skipped_item_keys,
                   applied_item_keys, failed_item_keys, current_step, total_steps)
                values ($1::uuid, 'queued', $2, $3, $4::text[], $5, $6, $7, $8,
                        $9, $10, $11, $12::uuid, $13::uuid, $14, $15, $16,
                        $17::jsonb, $18::text[], $19::text[], $20::text[],
                        '{}'::text[], '{}'::text[], 0, $21)
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
                source[2] if source else None,
                source[0] if source else None,
                source[1] if source else None,
                body.source_placement if source else None,
                body.source_campaign_id if source else None,
                # The authorisation this render runs under. Stamped once, at
                # submit, so a worker retry hours later — or the 5-minute stranded
                # recovery — re-runs a job that WAS authorised rather than asking
                # the database whether it still would be. Consent governs new
                # sharing; it does not retroactively cancel a render the user
                # already started and paid for.
                consent_version,
                json.dumps(look.as_json()),
                look.selected_item_keys,
                look.planned_item_keys,
                look.skipped_item_keys,
                look.total_steps,
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

            response = {
                "job_id": str(job_id),
                "status": "queued",
                "state": "queued",
                "total_steps": look.total_steps,
                "current_step": 0,
                "applied_item_keys": [],
                # Told at SUBMIT, not discovered at the end: a piece that will not
                # be rendered is something the user should hear about while they
                # can still do something about it (§29).
                "skipped": [
                    TryOnSkippedGarment(
                        item_key=s.item_key,
                        reason=s.reason,
                        message=s.message,
                        canonical=s.canonical,
                    ).model_dump()
                    for s in look.skipped
                ],
            }
            await store_response(conn, idempotency_key, user.id, _ENDPOINT, 202, response)
    timer.mark("create_and_reserve")

    # Wake the orchestrator AFTER the commit, outside any transaction (§11.5). Best-
    # effort: a failed signal leaves the job 'queued' for the 5-min recovery task, and
    # the DO bridge polls the DB (ignoring the stub queue), so this is harmless there.
    if await enqueue_signal(KIND_TRYON, str(job_id)):
        async with get_pool().acquire() as conn:
            await conn.execute(
                "update public.tryon_jobs set last_signal_at = now() where id = $1::uuid",
                str(job_id),
            )
    timer.mark("enqueue")
    return JSONResponse(status_code=202, content=response)


@router.get("/tryon/results", response_model=list[TryOnResultItem])
async def list_tryon_results(
    user: CurrentUser = Depends(get_current_user),
) -> list[TryOnResultItem]:
    """The user's saved try-on results, newest first — powers the history view."""
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            """
            select r.id, r.result_image_url, r.created_at, r.outcome,
                   j.source_kind, j.source_product_id, j.source_merchant_id,
                   j.source_placement, j.source_campaign_id
              from public.tryon_results r
              left join public.tryon_jobs j on j.id = r.job_id
             where r.user_id = $1::uuid
             order by r.created_at desc
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
                TryOnResultItem(
                    id=str(r["id"]),
                    result_image_url=url,
                    # `resolve_images` has always signed this alongside the full
                    # render, in the same batch; it was thrown away here, so the
                    # history grid had no choice but to draw the full render.
                    thumbnail_url=hit.thumb_url if hit else None,
                    created_at=r["created_at"],
                    source=_source_of(r),
                    outcome=r["outcome"],
                )
            )
    return items


@router.post("/tryon/results/{result_id}/feedback", response_model=TryOnFeedbackResponse)
async def submit_tryon_feedback(
    result_id: UUID,
    body: TryOnFeedback,
    user: CurrentUser = Depends(get_current_user),
) -> TryOnFeedbackResponse:
    """The user's verdict on a finished render: **Keep it** or **Not me** (§18).

    THIS ENDPOINT NEVER TOUCHES CREDITS. That is the whole point of separating
    it from the failure paths. A render that failed technically, or that lost a
    garment, or that the fidelity gate rejected, was already refunded by the
    worker before the user ever saw it (§19.1/§19.2). What arrives here is a
    render that WORKED and that the user simply does or does not want — a taste
    signal (§19.3). Refunding subjective dislike would turn "I'd rather see
    another" into a free-render loop, and would also be dishonest about what
    went wrong, because nothing did.

    Idempotent by construction: the outcome is stored on the result row and the
    Style Memory signal is deduped on that row's id, so a double tap, a retry
    after a dropped response, or a re-open of the result screen all converge on
    one recorded verdict. Changing your mind is allowed — the row is updated and
    the newer verdict wins — but it cannot double-weight the profile.
    """
    if body.outcome == "rejected" and body.reason is None:
        raise ApiError(
            ErrorCode.VALIDATION_ERROR,
            "Tell us what didn't work so we can learn from it.",
            422,
        )

    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            update public.tryon_results
               set outcome = $3, rejection_reason = $4, feedback_at = now()
             where id = $1::uuid and user_id = $2::uuid
            returning id, job_id
            """,
            str(result_id),
            user.id,
            body.outcome,
            body.reason,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Try-on result not found.", 404)

        # Style Memory is a separate, flagged subsystem. With the flag OFF the
        # verdict is still stored above — it is a fact about the render and it
        # feeds the cost ledger's "was this kept?" column either way — we simply
        # do not learn from it yet.
        recorded = False
        learned: str | None = None
        profile = None
        if await flag_enabled(conn, sm.FLAG_STYLE_MEMORY, default=False):
            before = await sm.get_profile(conn, user.id)
            context: dict = {"reason": body.reason} if body.reason else {}
            if body.note:
                context["note"] = body.note[:280]
            context.update(await sm.look_attributes(conn, str(row["job_id"])))
            try:
                recorded = await sm.record_signal(
                    conn,
                    user.id,
                    signal_type="keep_look" if body.outcome == "kept" else "reject_look",
                    entity_type="tryon_result",
                    entity_id=str(result_id),
                    value=body.reason,
                    context=context,
                    # One verdict per result, however many times it is sent.
                    dedupe_key=f"tryon_result:{result_id}:{body.outcome}",
                )
            except sm.StyleMemoryError as exc:
                raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc
            after = await sm.get_profile(conn, user.id)
            profile = StyleMemoryProfile(**after)
            summary = after.get("preference_summary")
            if recorded and summary and summary != before.get("preference_summary"):
                learned = summary

    log.info("tryon feedback result=%s outcome=%s", result_id, body.outcome)
    return TryOnFeedbackResponse(
        result_id=str(result_id),
        outcome=body.outcome,
        recorded=recorded,
        learned=learned,
        profile=profile,
    )


@router.delete("/tryon/results/{result_id}", status_code=204)
async def delete_tryon_result(
    result_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Remove one try-on result from the user's history, and erase its image.

    Scoped by `user_id` in the DELETE itself, so a result that is not yours is a
    404 rather than an authorization decision made after the read — the user id
    comes from the verified JWT and is never taken from the request (§11).

    What it erases is deliberately NARROW. A try-on has three images and only
    one of them belongs to this row:

      * the RESULT — this row's own render, and the only thing deleted here;
      * the person image — the user's body photo, owned by `tryon_photos` and
        reused by every future render;
      * the garment image — a wardrobe cutout or a catalog photo, owned by
        somebody else entirely.

    Deleting either of the last two would take a source image away from every
    other render that used it, which is why `refs` names the result and nothing
    else. A Saved Look is unaffected for the same reason: saving re-uploads the
    bytes to a separate durable object (`SaveLookService`), so the copy the user
    kept — and any community post carrying it — is a different object from the
    one erased here.

    The `tryon_jobs` row is left alone: it is the credit/audit record for a
    charge that really happened, and history is the result, not the job.

    Media erasure is best-effort by construction (`delete_content_media` never
    raises), so a storage hiccup cannot leave a row the user has been told is
    gone. The orphan is sweepable; a resurrected result is not.
    """
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            """
            delete from public.tryon_results
             where id = $1::uuid and user_id = $2::uuid
            returning id, result_image_url
            """,
            str(result_id),
            user.id,
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Try-on result not found.", 404)
        await delete_content_media(
            conn,
            "tryon_result",
            str(result_id),
            [("result", row["result_image_url"])],
        )
    log.info("tryon result deleted id=%s", result_id)
    return Response(status_code=204)


@router.get("/tryon/{job_id}", response_model=TryOnJobResponse)
async def get_tryon(
    job_id: UUID, user: CurrentUser = Depends(get_current_user)
) -> TryOnJobResponse:
    async with get_pool().acquire() as conn:
        job = await conn.fetchrow(
            """
            select id, status, error,
                   source_kind, source_product_id, source_merchant_id,
                   source_placement, source_campaign_id,
                   plan, applied_item_keys, current_step, total_steps
              from public.tryon_jobs
             where id = $1::uuid and user_id = $2::uuid
            """,
            str(job_id),
            user.id,
        )
        if job is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Job not found.", 404)

        result_image_url: str | None = None
        result_id: str | None = None
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
                result_id = str(res["id"])
                result_image_url = await _resolve_result(conn, res["id"], res["result_image_url"])

    return TryOnJobResponse(
        job_id=str(job["id"]),
        result_id=result_id,
        status=job["status"],
        result_image_url=result_image_url,
        error=job["error"],
        source=_source_of(job),
        total_steps=job["total_steps"],
        current_step=job["current_step"],
        applied_item_keys=list(job["applied_item_keys"] or []),
        skipped=_skipped_of(job["plan"]),
    )


def _skipped_of(plan: object) -> list[TryOnSkippedGarment]:
    """The plan's recorded skips, rehydrated for the client.

    The stored plan keeps codes, not display copy — a message written months ago
    should not be what a user reads today — so the sentence is re-derived from
    the current message table. A pre-0069 job has no plan and reports none, which
    is exactly what it was.
    """
    if not plan:
        return []
    try:
        data = plan if isinstance(plan, dict) else json.loads(plan)
        entries = data.get("skipped") or []
    except (ValueError, TypeError, AttributeError):
        return []
    out: list[TryOnSkippedGarment] = []
    for entry in entries:
        reason = str(entry.get("reason", ""))
        out.append(
            TryOnSkippedGarment(
                item_key=str(entry.get("item_key", "")),
                reason=reason,
                message=skip_message(reason),
                canonical=entry.get("canonical"),
            )
        )
    return out
