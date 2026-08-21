"""Try-on job draining (Render worker, CLAUDE.md §7).

Claims queued `tryon_jobs` one at a time (FOR UPDATE SKIP LOCKED so multiple
workers never grab the same row), runs the TryOnProvider, writes a result and
marks the job done — charging the credit ONLY on success (§7). Provider failures
mark the job failed and never charge. Every attempt is logged to ai_usage_log
(§14).
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from base64 import b64encode
from decimal import Decimal

import asyncpg

from app.core.config import get_settings
from app.core.credits import refund_credit
from app.core.timing import StageTimer, current_timer, trace_token
from app.services.billing import user_plan
from app.services.llm import get_fidelity_judge
from app.services.media import get_storage_provider
from app.services.media.refresh import freshen_media_url
from app.services.media.repo import insert_asset
from app.services.notifications import create_notification
from app.services.storage import download_image, upload_tryon_result
from app.services.tryon import get_tryon_provider
from app.services.tryon.base import (
    RenderRequest,
    RenderResult,
    TryOnCapacityError,
    TryOnInputError,
    TryOnProvider,
    TryOnTransientError,
)
from app.services.tryon.execution import ExecutedLook, LookIncompleteError, plan_steps_for
from app.services.tryon.fidelity import (
    STATUS_UNVERIFIED,
    FidelityOutcome,
    InspectionTarget,
    LookFidelityError,
    inspect_look,
    user_message_for,
)

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

# Provider refused outright (429 — rate limit / FASHN account out of credits).
# Distinct message so the user knows it's the studio, not their photo, and that
# nothing was charged (§13). The raw 429 body is in the logs for the founder.
_CAPACITY_MSG = (
    "The AI studio is temporarily unavailable, so this render couldn't run. "
    "Your credits were refunded — please try again later."
)


# A look whose chain finished but did not apply every garment the user picked.
# Deliberately NOT phrased as a provider glitch: the user chose four things and
# got fewer, and the honest thing to say is that we would not hand them a look
# that was missing pieces.
_INCOMPLETE_MSG = (
    "We couldn't put the whole look together, so we didn't charge you for a "
    "partial one. Your credits were refunded — please try again."
)


def _exhausted_message(exc: Exception) -> str:
    """User-safe message for a failure after retries: capacity gets its own."""
    return _CAPACITY_MSG if isinstance(exc, TryOnCapacityError) else _RETRY_EXHAUSTED_MSG


async def _run_fidelity_gate(
    *,
    job_id: object,
    result_url: str,
    steps: list,
    attempt: int,
) -> FidelityOutcome:
    """Inspect the finished render against the garments that were selected.

    Runs AFTER the completeness invariant and BEFORE the result is persisted, so
    a rejected look never exists as a finished render — exactly where
    `require_complete()` sits, and for the same reason. `require_complete` proves
    every garment was applied; this proves the applied garment is the one the
    user picked.

    Never raises for its own failure: an unreachable judge or an undownloadable
    reference is `unverified`, and the caller decides what that is worth.
    """
    settings = get_settings()
    if not settings.fashn_fidelity_gate_enabled:
        return FidelityOutcome(status="skipped")

    judge = get_fidelity_judge()
    targets: list[InspectionTarget] = []
    for step in steps:
        try:
            garment = await download_image(await freshen_media_url(step.image_url))
        except Exception as exc:  # noqa: BLE001 — no reference is not a bad render
            log.warning(
                "fidelity: could not read reference for job %s step %s: %s",
                job_id,
                step.index,
                exc,
            )
            continue
        targets.append(
            InspectionTarget(
                item_key=step.item_key,
                canonical=step.canonical,
                garment_bytes=garment,
                garment_media_type=_media_type_of(garment),
            )
        )

    if not targets:
        return FidelityOutcome(status=STATUS_UNVERIFIED, detail="no reference image readable")

    try:
        render = await download_image(result_url)
    except Exception as exc:  # noqa: BLE001
        return FidelityOutcome(status=STATUS_UNVERIFIED, detail=f"render unreadable: {exc}"[:200])

    outcome = await inspect_look(
        judge,
        render=render,
        render_media_type=_media_type_of(render),
        targets=targets,
    )
    log.info(
        "tryon fidelity job=%s attempt=%d status=%s inspected=%d codes=%s "
        "judge=%s tokens_in=%d tokens_out=%d",
        job_id,
        attempt,
        outcome.status,
        outcome.inspected,
        ",".join(outcome.codes) or "-",
        judge.name,
        outcome.input_tokens,
        outcome.output_tokens,
    )
    return outcome


async def _render_chain(
    conn: asyncpg.Connection,
    *,
    provider: object,
    job_id: object,
    steps: list,
    look: ExecutedLook,
    person_image: str,
    fallback_url: str,
) -> str:
    """Run the planned steps in order and return the FINAL image url.

    Extracted so a look can be rebuilt from the user's own photo after a fidelity
    rejection. The chain is cumulative — each render's output is the next
    render's model image — so it cannot be resumed from the middle: a step that
    produced the wrong garment has poisoned everything downstream of it.

    `current` is only ever reassigned to a step that SUCCEEDED, so the chain can
    never silently fall back to the original photo mid-sequence and lose the
    garments already applied.
    """
    current = person_image
    result_url = fallback_url  # only reached if the plan is empty
    for position, step in enumerate(steps):
        step_started = time.monotonic()
        # Re-sign the garment fresh too: FASHN fetches it by URL, so a stale
        # closet presigned URL would 404 there just like it did at moderation.
        request = RenderRequest(
            person_image=current,
            garment_image=await freshen_media_url(step.image_url),
            model_name=step.model_name,
            category=step.category,
            prompt=step.prompt,
            garment_photo_type=step.garment_photo_type,
            is_final=position == len(steps) - 1,
        )
        try:
            rendered, attempts = await _render_with_retry(
                provider, request, job_id=job_id, step_index=step.index
            )
        except Exception:
            look.record_failure(step, attempts=_MAX_ATTEMPTS, duration_ms=_ms_since(step_started))
            await _save_progress(conn, job_id, look, current_step=position)
            raise
        look.record_success(
            step,
            attempts=attempts,
            duration_ms=_ms_since(step_started),
            prediction_id=rendered.prediction_id,
        )
        # One structured line per step (§24). Safe identifiers only: no image,
        # no signed URL, no secret — the prediction id is the join key back to
        # the provider.
        log.info(
            "tryon step job=%s step=%d role=%s model=%s prediction=%s attempts=%d duration_ms=%d",
            job_id,
            step.index,
            step.canonical,
            step.model_name,
            rendered.prediction_id,
            attempts,
            _ms_since(step_started),
        )
        result_url = rendered.image_url
        current = result_url
        # Progress is persisted per step, not per job: a look that dies on step 3
        # says which two garments it had already applied, and the app can show
        # "2 of 4" while it is still running.
        await _save_progress(conn, job_id, look, current_step=position + 1)
    return result_url


def _media_type_of(image: bytes) -> str:
    """The vision API needs a declared media type, and a wrong one is rejected."""
    if image[:8].startswith(b"\x89PNG"):
        return "image/png"
    if image[:4] == b"RIFF" and image[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


def _ms_since(started: float) -> int:
    return int((time.monotonic() - started) * 1000)


async def _save_progress(
    conn: asyncpg.Connection, job_id: object, look: ExecutedLook, *, current_step: int
) -> None:
    """Persist step-by-step progress. Best-effort: a bookkeeping write must never
    be the thing that fails a render the user has already paid for."""
    try:
        await conn.execute(
            """
            update public.tryon_jobs
               set applied_item_keys = $2::text[],
                   failed_item_keys  = $3::text[],
                   step_state        = $4::jsonb,
                   current_step      = $5
             where id = $1::uuid
            """,
            str(job_id),
            look.applied,
            look.failed,
            json.dumps(look.step_state),
            current_step,
        )
    except Exception as exc:  # noqa: BLE001 - progress is observability, not state
        log.warning("try-on job %s progress write failed: %s", job_id, exc)


async def _render_with_retry(
    provider: TryOnProvider,
    request: RenderRequest,
    *,
    job_id: object,
    step_index: int,
) -> tuple[RenderResult, int]:
    """Run one planned step, retrying transient failures with backoff. Permanent
    input errors (and our own timeout) propagate immediately — retrying won't help.

    Returns the step result — image URL plus the provider's own run id — and the
    attempt count, so `step_state` records how hard a step was and WHICH provider
    run produced it, not merely whether it worked (§18/§24).

    A retry re-submits the SAME step with the SAME inputs. It never advances the
    chain and never re-renders an earlier garment, so no retry can duplicate work
    the look has already banked — and FASHN does not bill a failed prediction, so
    a retried step costs one external credit, not one per attempt (§19)."""
    last: TryOnTransientError | None = None
    for attempt in range(1, _MAX_ATTEMPTS + 1):
        try:
            return await provider.render(request), attempt
        except TryOnTransientError as exc:
            last = exc
            log.warning(
                "try-on job %s step %d attempt %d/%d transient failure: %s",
                job_id,
                step_index,
                attempt,
                _MAX_ATTEMPTS,
                exc,
            )
            if attempt < _MAX_ATTEMPTS:
                await asyncio.sleep(_BACKOFF_BASE * (2 ** (attempt - 1)))
    assert last is not None  # loop only exits via return or after setting `last`
    raise last


def _downscale(image: bytes, max_edge: int) -> tuple[bytes, str]:
    """Shrink the body photo to `max_edge` on its long side, as JPEG.

    The provider renders at 864x1296 whatever we send, and this image travels as
    base64 inside the /v1/run body — a 600 KB camera photo becomes ~800 KB of
    JSON and made FASHN's own ingestion the slowest call of the first step
    (measured 6.3 s in production). Downscaling once, here, is the whole fix.

    Best-effort by construction: any decode failure returns the original bytes,
    because a render that works slowly is strictly better than one that doesn't."""
    if max_edge <= 0:
        return image, "image/jpeg"
    try:
        from io import BytesIO

        from PIL import Image, ImageOps

        with Image.open(BytesIO(image)) as img:
            # Honour the camera's rotation before measuring, or a portrait photo
            # taken sideways gets resized against the wrong edge.
            img = ImageOps.exif_transpose(img)
            if max(img.size) <= max_edge and img.format == "JPEG":
                return image, "image/jpeg"
            img.thumbnail((max_edge, max_edge), Image.LANCZOS)
            buffer = BytesIO()
            img.convert("RGB").save(buffer, format="JPEG", quality=90, optimize=True)
            return buffer.getvalue(), "image/jpeg"
    except Exception as exc:  # noqa: BLE001 - preprocessing is best-effort
        log.warning("person image downscale failed; sending original: %s", exc)
        ctype = "image/png" if image[:8].startswith(b"\x89PNG") else "image/jpeg"
        return image, ctype


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
    through unchanged — those are already fetchable.

    Done ONCE per job (§14): only the first step sends the body this way, and
    every later step chains the previous step's output URL, so the decode/resize
    below is never repeated within a look."""
    try:
        image = await download_image(url)
    except Exception as exc:
        raise TryOnInputError(
            "We couldn't load your try-on photo. Please re-select your photo and try again."
        ) from exc
    image, ctype = _downscale(image, get_settings().tryon_person_max_edge)
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
                  garment_image_urls, provider, hd, idempotency_key,
                  plan, planned_item_keys, applied_item_keys
        """
    )


async def _charged_credits(conn: asyncpg.Connection, user_id: object, job_id: object) -> int | None:
    """What this job actually cost the user, from `credit_transactions`.

    The spend ledger stays the authority (spec §33: link, do not duplicate);
    this only copies the number onto the cost row so margin is a single-table
    query. Null for a legacy job that predates reserve-at-submit.
    """
    try:
        delta = await conn.fetchval(
            "select delta from public.credit_transactions "
            "where user_id = $1::uuid and ref = $2 and reason = 'spend'",
            str(user_id),
            str(job_id),
        )
    except Exception as exc:  # noqa: BLE001 - instrumentation is never load-bearing
        log.warning("charged-credit lookup failed for job %s: %s", job_id, exc)
        return None
    return abs(int(delta)) if delta is not None else None


async def _plan_tier(conn: asyncpg.Connection, user_id: object) -> str | None:
    """The subscription tier this user is on, for COGS-by-tier. Best-effort:
    an unreadable tier is a null column, never a failed render."""
    try:
        return (await user_plan(conn, str(user_id))).tier
    except Exception as exc:  # noqa: BLE001 - instrumentation is never load-bearing
        log.warning("plan tier lookup failed for %s: %s", user_id, exc)
        return None


def _ledger_shape(look: ExecutedLook | None, steps: list | None) -> dict[str, object]:
    """The provider-economics facts for one render, read off what actually ran.

    Derived from `step_state` rather than from the plan, because the plan says
    what we INTENDED and the ledger has to record what we PAID for. A step that
    was retried three times is three provider submissions in the log and one
    charge to the user — those are different numbers and the ledger keeps both.
    """
    endpoints: list[str] = []
    attempts = 0
    if look is not None:
        for entry in look.step_state.values():
            model = entry.get("model")
            if model and model not in endpoints:
                endpoints.append(str(model))
            attempts += max(0, int(entry.get("attempts") or 1) - 1)
    if not endpoints and steps:
        endpoints = sorted({s.model_name for s in steps if getattr(s, "model_name", None)})
    return {
        # Multiple models can appear in ONE look (apparel chained into
        # accessories), so the endpoint column records the chain, not a guess.
        "endpoint": "+".join(endpoints) or None,
        "technical_retries": attempts,
    }


async def _log_usage(
    conn: asyncpg.Connection,
    *,
    user_id: object,
    provider: str,
    success: bool,
    latency_ms: int,
    images: int = 1,
    job_id: object = None,
    endpoint: str | None = None,
    mode: str | None = None,
    resolution: str | None = None,
    wtm_credit_cost: int | None = None,
    technical_retries: int | None = None,
    quality_retries: int | None = None,
    quality_state: str | None = None,
    plan_tier: str | None = None,
) -> None:
    """Append one row to the cost ledger (§14, spec §33).

    `images` is the number of provider OUTPUTS this job produced — one per
    chained garment step — and is also the external unit count, because both
    FASHN models this pipeline uses bill a flat one credit per output at the
    settings `services/tryon/routing.py` pins.

    Every new column is optional. A caller that does not know a value passes
    nothing and the column stays null, which is how this stayed a safe additive
    change to a table three other subsystems already write to.
    """
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, images, estimated_usd, latency_ms, success,
           job_id, endpoint, mode, resolution, external_units, wtm_credit_cost,
           technical_retries, quality_retries, quality_state, plan_tier)
        values ($1::uuid, $2, 'tryon', $3, $4, $5, $6,
                $7::uuid, $8, $9, $10, $11, $12, $13, $14, $15, $16)
        """,
        str(user_id),
        provider,
        images,
        _PROVIDER_USD.get(provider, Decimal("0")) * images,
        latency_ms,
        success,
        str(job_id) if job_id is not None else None,
        endpoint,
        mode,
        resolution,
        Decimal(images),
        wtm_credit_cost,
        technical_retries,
        quality_retries,
        quality_state,
        plan_tier,
    )


#: Longest error sentence we will repeat back to a user in a notification body.
_REASON_MAX = 140

#: Fallback when the stored error is empty or does not look like user-facing
#: copy. Never risk echoing an internal string into a notification.
_GENERIC_REASON = "Please try again with a different photo."


def _user_safe_reason(error: str) -> str:
    """A short, user-safe reason to append to a failure notification.

    The provider layer already maps FASHN's terminal errors to friendly
    sentences, but this is the last gate before text reaches a user's lock
    screen, so it re-checks rather than trusts: anything carrying the shape of a
    URL, a token, a payload dump or a traceback is replaced wholesale.
    """
    reason = (error or "").strip()
    if not reason:
        return _GENERIC_REASON
    lowered = reason.lower()
    leaky = ("http://", "https://", "traceback", "{", "}", "x-amz", "bearer ", "signature=")
    if any(marker in lowered for marker in leaky):
        return _GENERIC_REASON
    return reason[:_REASON_MAX]


async def _mark_failed(conn: asyncpg.Connection, job_id: object, error: str) -> None:
    await conn.execute(
        "update public.tryon_jobs set status = 'failed', error = $2 where id = $1::uuid",
        str(job_id),
        error[:500],
    )


async def _fail_and_refund(
    conn: asyncpg.Connection,
    *,
    job_id: object,
    user_id: object,
    error: str,
    provider: str,
    latency_ms: int,
    images: int,
    ledger: dict[str, object] | None = None,
) -> None:
    """A try-on job failed: mark it failed and REFUND the credits reserved at
    submit (§7), atomically, then log the (failed) usage. The refund is idempotent
    and a no-op for legacy jobs that were never reserved, so this is always safe."""
    async with conn.transaction():
        await _mark_failed(conn, job_id, error)
        await refund_credit(conn, str(user_id), ref=str(job_id))
        # Same transaction as the failure AND the refund: a user is never told
        # about a refund that did not happen, and never left wondering about a
        # render they paid for and never saw. Deduped on the job, so a recovery
        # re-claim cannot say it twice.
        await create_notification(
            conn,
            user_id=str(user_id),
            type="try_on_ready",
            title="Your try-on didn't work out",
            # The refund is the part they most need to know, so it is stated
            # first and unconditionally. `error` is already the user-safe
            # sentence the provider layer mapped — raw payloads, signed URLs and
            # stack traces never reach it (see services/tryon/fashn.py).
            body=f"Your credits were refunded. {_user_safe_reason(error)}".strip(),
            target_type="tryon_result",
            target_id=None,
            dedupe_key=f"tryon_job:{job_id}:failed",
            data={"job_id": str(job_id)},
        )
    await _log_usage(
        conn,
        user_id=user_id,
        provider=provider,
        success=False,
        latency_ms=latency_ms,
        images=images,
        job_id=job_id,
        **(ledger or {}),  # type: ignore[arg-type]
    )


async def process_job(conn: asyncpg.Connection, job: asyncpg.Record) -> None:
    """Render one queued try-on.

    Wrapped so every exit path emits its stage timings (§14). The timer is
    ambient (a ContextVar), which is what lets the FASHN provider contribute
    `provider_accept` and `provider_inference` without this function's helpers
    growing a parameter they would otherwise never use.
    """
    timer = StageTimer(
        scope="tryon.worker",
        trace=trace_token(job["idempotency_key"] if "idempotency_key" in job else None),
    )
    token = current_timer.set(timer)
    try:
        await _process_job(conn, job, timer)
    finally:
        timer.emit()
        current_timer.reset(token)
        # Persist the stage breakdown on the job itself, not only in the log
        # stream. A slow render is diagnosable from its job id afterwards, which
        # is the point of §24 — a log line that has aged out of retention is not
        # evidence. Durations and counts only; never a URL or an image (§14).
        await _save_timings(conn, job["id"], timer)
        # Release the provider's pooled connections. They are reused across every
        # step of THIS look (which is what removed a TLS handshake per step) and
        # must not outlive the job in a batch worker that goes on to the next one.
        closer = getattr(get_tryon_provider(), "aclose", None)
        if closer is not None:
            try:
                await closer()
            except Exception as exc:  # noqa: BLE001 - cleanup must never fail a job
                log.warning("provider close failed for job %s: %s", job["id"], exc)


async def _save_timings(conn: asyncpg.Connection, job_id: object, timer: StageTimer) -> None:
    """Best-effort: store the stage timings as JSON on the job."""
    try:
        await conn.execute(
            "update public.tryon_jobs set timings = $2::jsonb where id = $1::uuid",
            str(job_id),
            json.dumps(timer.as_dict()),
        )
    except Exception as exc:  # noqa: BLE001 - instrumentation is never load-bearing
        log.warning("try-on job %s timing write failed: %s", job_id, exc)


async def _process_job(conn: asyncpg.Connection, job: asyncpg.Record, timer: StageTimer) -> None:
    job_id, user_id = job["id"], job["user_id"]
    provider = get_tryon_provider()
    started = time.monotonic()

    # THE PLAN, as it was fixed at submit. The worker executes it; it never
    # re-derives roles, re-orders steps or decides what a garment is.
    steps = plan_steps_for(job)
    planned = list(job["planned_item_keys"] or []) or [s.item_key for s in steps]
    look = ExecutedLook(planned=planned)
    stack = [s.image_url for s in steps]

    fidelity = FidelityOutcome(status="skipped")
    # Bound BEFORE the try so every failure path can report them, including one
    # that fires before the render loop is ever entered.
    look_attempt = 0
    # The tier this render was produced under, captured at execution time. Read
    # once (not per exit path) and never re-read afterwards: a subscription that
    # lapses tomorrow must not silently re-price yesterday's COGS.
    plan_tier = await _plan_tier(conn, user_id)

    try:
        # Hand the provider the user's photo as inline base64 (not the private,
        # expiring signed URL) so it never has to fetch it — see
        # _inline_person_image for the full root-cause note. The stored URL is
        # re-signed FRESH first, so a job re-run by recovery hours later (past the
        # original 1 h TTL) still resolves its own photo.
        log.info(
            "processing try-on job %s (%d step(s): %s)",
            job_id,
            len(steps),
            ",".join(s.canonical for s in steps),
        )
        # Download + resize + base64 of the body photo, ONCE per job. Measured on
        # its own because it is a full image fetch plus a 33% payload inflation,
        # and it is the input FASHN spends the longest ingesting.
        person_image = await _inline_person_image(await freshen_media_url(job["person_image_url"]))
        timer.mark("person_inline", len(person_image))
        # MULTI-GARMENT STRATEGY: no provider we can use renders a whole look at
        # once — FASHN's `tryon-max` explicitly rejects a `product_images` array
        # and `tryon-v1.6` takes one `garment_image` (both verified against the
        # live API on 2026-08-15) — so we CHAIN: each render's output becomes the
        # next render's MODEL image, in the planner's order (one-piece/bottom/top
        # → outerwear → shoes/bag → head → face → jewellery).
        #
        # The chain is what makes the look cumulative. `current` is only ever
        # reassigned to the step that just succeeded, so it can never fall back to
        # the original photo mid-sequence and lose the garments already applied.
        # Accessories run last on the prompt-steerable model precisely because an
        # apparel pass repaints a whole body region and would erase them.
        result_url = job["person_image_url"]  # only reached if the plan is empty
        max_fidelity_retries = get_settings().fashn_fidelity_max_retries
        for look_attempt in range(max_fidelity_retries + 1):
            if look_attempt:
                # A re-render, not a resume. The chain is cumulative, so a look
                # that produced the wrong garment cannot be patched from the
                # middle — it has to be rebuilt from the user's own photo.
                look = ExecutedLook(planned=planned)
                log.warning(
                    "try-on job %s re-rendering after fidelity rejection (attempt %d/%d, codes=%s)",
                    job_id,
                    look_attempt + 1,
                    max_fidelity_retries + 1,
                    ",".join(fidelity.codes) or "-",
                )
            current = person_image
            result_url = await _render_chain(
                conn,
                provider=provider,
                job_id=job_id,
                steps=steps,
                look=look,
                person_image=current,
                fallback_url=job["person_image_url"],
            )
            timer.mark("render_stack", len(steps))

            # THE FULL LOOK INVARIANT (§7, spec Phase 7). Checked BEFORE the
            # result is persisted, so a look that lost a garment never exists as
            # a finished render at all. This is the line that makes "only the
            # shirt came back" a failure with a refund instead of a success with
            # a charge.
            look.require_complete()

            # THE FIDELITY GATE (§19, §29). Completeness proves every garment was
            # applied; this proves the applied garment is the one that was
            # chosen. A render that materially redesigned the piece is not a
            # result, however convincing the photograph.
            fidelity = await _run_fidelity_gate(
                job_id=job_id,
                result_url=result_url,
                steps=steps,
                attempt=look_attempt + 1,
            )
            timer.mark("fidelity_gate", fidelity.inspected)
            if not fidelity.rejected:
                break
        if fidelity.rejected:
            raise LookFidelityError(fidelity.codes, fidelity.detail or "")
        if fidelity.status == STATUS_UNVERIFIED and get_settings().fashn_fidelity_fail_closed:
            # The operator has chosen refusal over delivering something nobody
            # inspected. Distinct from a rejection: nothing was found wrong.
            raise LookFidelityError([STATUS_UNVERIFIED], fidelity.detail or "")
    except LookFidelityError as exc:
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn,
            job_id=job_id,
            user_id=user_id,
            error=user_message_for(exc.codes),
            provider=provider.name,
            latency_ms=latency,
            images=len(steps),
            ledger={
                **_ledger_shape(look, steps),
                "quality_state": "rejected",
                # The look was rebuilt from scratch each time the gate refused
                # it, so the retries are look-level, not step-level.
                "quality_retries": look_attempt,
                "wtm_credit_cost": 0,  # refunded above — the user paid nothing
                "plan_tier": plan_tier,
            },
        )
        log.error(
            "try-on job %s REJECTED by fidelity gate, refunded: codes=%s detail=%s",
            job_id,
            ",".join(exc.codes),
            exc.detail,
        )
        return

    except LookIncompleteError as exc:
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn,
            job_id=job_id,
            user_id=user_id,
            error=_INCOMPLETE_MSG,
            provider=provider.name,
            latency_ms=latency,
            images=len(steps),
            ledger={
                **_ledger_shape(look, steps),
                "quality_state": "incomplete",
                "wtm_credit_cost": 0,
                "plan_tier": plan_tier,
            },
        )
        log.error("try-on job %s incomplete, refunded: missing=%s", job_id, exc.missing)
        return
    except TryOnInputError as exc:
        # Permanent + user-actionable (bad pose, NSFW, unreadable photo): show the
        # specific guidance so the user can fix it, and refund the reserve (§7).
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn,
            job_id=job_id,
            user_id=user_id,
            error=str(exc),
            provider=provider.name,
            latency_ms=latency,
            images=len(stack),
            ledger={
                **_ledger_shape(look, steps),
                "quality_state": "input_rejected",
                "wtm_credit_cost": 0,
                "plan_tier": plan_tier,
            },
        )
        log.warning("try-on job %s failed (input), refunded: %s", job_id, exc)
        return
    except Exception as exc:  # transient exhausted / timeout / unexpected -> fail
        # Retries are spent (or it timed out) — surface a clean message (capacity
        # failures get their own); the raw error is logged for diagnosis. Refund
        # the reserve (§7).
        latency = int((time.monotonic() - started) * 1000)
        await _fail_and_refund(
            conn,
            job_id=job_id,
            user_id=user_id,
            error=_exhausted_message(exc),
            provider=provider.name,
            latency_ms=latency,
            images=len(stack),
            ledger={
                **_ledger_shape(look, steps),
                "quality_state": "failed",
                "wtm_credit_cost": 0,
                "plan_tier": plan_tier,
            },
        )
        log.warning("try-on job %s failed after retries, refunded: %s", job_id, exc)
        return

    latency = int((time.monotonic() - started) * 1000)

    # Persist the result into our own storage so the user's history survives the
    # provider's short output retention (§8). Best-effort: if it fails we keep the
    # provider URL so the run still delivers a result.
    stored_result = result_url
    content_type = "image/jpeg"
    result_asset = None
    try:
        content_type = (
            "image/png" if result_url.split("?")[0].lower().endswith(".png") else "image/jpeg"
        )
        image = await download_image(result_url)
        timer.mark("result_download", len(image))
        if get_settings().r2_writes_enabled:
            # New path: store the private result in R2; the column holds the
            # object_key and the read endpoint signs it on serve (§8).
            result_asset = await get_storage_provider().put(
                image,
                visibility="private",
                prefix=f"{user_id}/result",
                content_type=content_type,
                # History draws results in a three-across grid.
                # `list_tryon_results` already batch-resolves a thumbnail for
                # every row — it was resolving None for all of them, because
                # none was ever generated.
                make_thumbnail=True,
            )
            stored_result = result_asset.object_key
        else:
            stored_result = await upload_tryon_result(str(user_id), image, content_type)
        timer.mark("result_store")
    except Exception as exc:
        log.warning(
            "persisting try-on result for job %s failed; keeping provider URL: %s",
            job_id,
            exc,
        )

    # Persist result + mark done atomically. The credits were already RESERVED at
    # submit (§7/§12) — success keeps them; we never charge again here, so a
    # re-processed job can't double-charge. A failure path above refunds instead.
    async with conn.transaction():
        result_id = await conn.fetchval(
            """
            insert into public.tryon_results (job_id, user_id, result_image_url)
            values ($1::uuid, $2::uuid, $3)
            returning id
            """,
            str(job_id),
            str(user_id),
            stored_result,
        )
        if result_asset is not None:
            await insert_asset(
                conn,
                owner_kind="tryon_result",
                owner_id=result_id,
                role="result",
                user_id=user_id,
                visibility="private",
                storage_provider="r2",
                object_key=result_asset.object_key,
                thumbnail_key=result_asset.thumbnail_key,
                content_hash=result_asset.content_hash,
                mime_type=content_type,
            )
        await conn.execute(
            """
            update public.tryon_jobs
               set status = 'done', error = null,
                   applied_item_keys = $2::text[],
                   failed_item_keys  = $3::text[],
                   step_state        = $4::jsonb,
                   current_step      = $5,
                   total_steps       = coalesce(total_steps, $5)
             where id = $1::uuid
            """,
            str(job_id),
            look.applied,
            look.failed,
            json.dumps(look.step_state),
            len(look.applied),
        )
        # A try-on takes 5-20s and the user often leaves the generating screen, so
        # the result has to find them. Same transaction as the completion, deduped
        # on the job id so a recovery re-claim cannot announce it twice.
        await create_notification(
            conn,
            user_id=str(user_id),
            type="try_on_ready",
            title="Your try-on is ready",
            body="Tap to see how it looks on you.",
            target_type="tryon_result",
            target_id=str(result_id),
            dedupe_key=f"tryon_job:{job_id}:done",
            data={"job_id": str(job_id), "result_id": str(result_id)},
        )

    timer.mark("mark_done")
    # The successful render's cost row. `wtm_credit_cost` is what the user was
    # actually charged at submit — read from the ledger of record rather than
    # recomputed from the current policy, so a config change tomorrow cannot
    # rewrite what yesterday's render cost them.
    await _log_usage(
        conn,
        user_id=user_id,
        provider=provider.name,
        success=True,
        latency_ms=latency,
        images=len(stack),
        job_id=job_id,
        **_ledger_shape(look, steps),  # type: ignore[arg-type]
        quality_retries=look_attempt,
        quality_state=fidelity.status,
        plan_tier=plan_tier,
        wtm_credit_cost=await _charged_credits(conn, user_id, job_id),
    )
    log.info("try-on job %s done", job_id)


async def run_once(conn: asyncpg.Connection) -> bool:
    """Claim and process a single queued job. Returns True if one was processed."""
    job = await claim_next_job(conn)
    if job is None:
        return False
    await process_job(conn, job)
    return True
