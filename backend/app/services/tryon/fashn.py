"""FASHN.ai try-on provider (CLAUDE.md §2.2) — commercial API, ~$0.075/image.

Submits a run, polls status to completion, returns the result image URL. The key
is backend-only (§11). Network/timeout/failed-run errors raise so the worker marks
the job failed and never charges (§7). Swappable for self-hosted Leffa later.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass

import httpx

from app.services.tryon.base import (
    TryOnCapacityError,
    TryOnInputError,
    TryOnProvider,
    TryOnTransientError,
)

log = logging.getLogger("fashionos.tryon.fashn")

_TERMINAL_OK = "completed"
# Every terminal state FASHN can report that is NOT success. Treating all of them
# as terminal here is what stops a canceled/timed-out prediction from being polled
# all the way to our own ceiling and surfacing as a generic timeout (CLAUDE.md §7).
_TERMINAL_FAIL = frozenset({"failed", "canceled", "time_out", "timed_out"})

# Map FASHN's terminal error names to clear, user-facing, actionable messages
# (the raw payload like "{'name': 'PoseError', ...}" must never reach the user).
_FRIENDLY_ERRORS = {
    "PoseError": (
        "We couldn't detect your body in your photo. Use a clear, full-body "
        "photo of yourself — standing, facing the camera, with good lighting."
    ),
    "ImageLoadError": "We couldn't load one of the images. Please try a different photo.",
    "PhotoTypeError": "Please use a clear photo of a person for your avatar.",
    "ContentModerationError": "That image can't be used. Please choose a different one.",
    "NSFWError": "That image can't be used. Please choose a different one.",
}

# Terminal-failure names that are the USER's input and won't change on retry — so
# we fail fast with the specific guidance instead of burning retries. Anything
# else terminal (generic "failed"/"canceled"/"time_out", or a transport blip) is
# treated as transient and retried by the worker (CLAUDE.md §7).
_PERMANENT_ERRORS = frozenset(
    {"PoseError", "PhotoTypeError", "ContentModerationError", "NSFWError"}
)


def _friendly_fashn_error(error: object) -> str:
    """Turn FASHN's `{name, message}` error into a clean, actionable sentence."""
    name = error.get("name") if isinstance(error, dict) else None
    if isinstance(name, str) and name in _FRIENDLY_ERRORS:
        return _FRIENDLY_ERRORS[name]
    return "We couldn't generate your try-on. Please try a different photo."


def _classify_http_error(exc: httpx.HTTPStatusError) -> Exception:
    """A 429/5xx from FASHN is transient (retry); other 4xx won't fix on retry.
    429 gets its own class: it's a rate limit OR an empty FASHN credit balance —
    the worker stores a capacity-specific message when retries exhaust (§13)."""
    code = exc.response.status_code
    if code == 429:
        # Log the body — FASHN says whether it's rate limiting or out of credits.
        log.warning("FASHN 429 body: %s", exc.response.text[:300])
        return TryOnCapacityError(f"FASHN HTTP 429: {exc.response.text[:200]}")
    if code >= 500:
        return TryOnTransientError(f"FASHN HTTP {code}")
    return TryOnInputError("We couldn't generate your try-on. Please try again.")


# ── FASHN spend cap: a PER-MODEL external-credit budget (§14) ────────────────
# Pricing (help.fashn.ai/plans-and-pricing/api-pricing, 2026-07):
#   * Virtual Try-On tryon-v1.6: FLAT 1 credit per output — any `mode`.
#   * Image-generation models (edit, product-to-model, model-create, model-swap,
#     face-to-model, reframe, try-on-max…): fast/balanced/quality = 1/2/3 at 1k,
#     +1 per resolution step (2k/4k), × num_images; face reference +3.
# EVERY call funnels through `_run_outputs`, which pins each generation model to
# the BEST-QUALITY settings within ITS budget (below) and refuses to submit
# anything the estimator prices above that budget. Retries re-enter the same
# funnel, so no retry can escalate cost.
#
# AI Enhance (`edit`) renders at balanced·1k = 2 credits for a premium,
# product-preserving result — fast·1k (1 credit) looked visibly degraded. Every
# OTHER generation model stays on the cheapest fast·1k·single-output = 1 credit;
# raising Enhance here does NOT change try-on, catalog, or model-create pricing.

# Models billed at a flat 1 credit per output (no mode/resolution multipliers).
_FLAT_ONE_CREDIT_MODELS = frozenset({"background-remove"})

_GEN_MODE_CREDITS = {"fast": 1, "balanced": 2, "quality": 3}
_RESOLUTION_SURCHARGE = {"1k": 0, "2k": 1, "4k": 2}


@dataclass(frozen=True)
class _GenBudget:
    """Best-quality render settings within a per-model external-FASHN-credit cap."""

    max_credits: int
    generation_mode: str
    resolution: str


# Default for a generation model: cheapest fast·1k·single-output = 1 credit.
_DEFAULT_GEN_BUDGET = _GenBudget(max_credits=1, generation_mode="fast", resolution="1k")
# Per-model overrides. ONLY AI Enhance is raised (balanced·1k = 2 credits).
_GEN_BUDGET: dict[str, _GenBudget] = {
    "edit": _GenBudget(max_credits=2, generation_mode="balanced", resolution="1k"),
}


def _budget_for(model_name: str) -> _GenBudget:
    return _GEN_BUDGET.get(model_name, _DEFAULT_GEN_BUDGET)


# The highest external cost any single result may reach across all models (=2, the
# Enhance budget). Kept as a module constant for tests / documentation.
MAX_FASHN_CREDITS_PER_RESULT = max(
    [_DEFAULT_GEN_BUDGET.max_credits, *(b.max_credits for b in _GEN_BUDGET.values())]
)


def fashn_estimated_credits(model_name: str, inputs: dict) -> int:
    """Estimated FASHN credits PER GENERATED RESULT for a /v1/run payload,
    from the published pricing table. Unknown values price pessimistically so
    a new/unexpected setting can never sneak past the cap as "free"."""
    if model_name.startswith("tryon-v") or model_name in _FLAT_ONE_CREDIT_MODELS:
        return 1
    mode = inputs.get("generation_mode")
    # Omitted mode bills as fast@1k / balanced@2k+ ("automatic pricing").
    resolution = str(inputs.get("resolution", "1k"))
    if mode is None:
        mode = "fast" if resolution == "1k" else "balanced"
    per_image = _GEN_MODE_CREDITS.get(str(mode), 99) + _RESOLUTION_SURCHARGE.get(resolution, 99)
    if inputs.get("face_reference") or inputs.get("face_image"):
        per_image += 3
    return per_image


def _capped_inputs(model_name: str, inputs: dict) -> dict:
    """Pin a payload to the model's budget settings (never raises for our own
    callers — the tap still runs, just at the budgeted quality/resolution)."""
    if model_name.startswith("tryon-v") or model_name in _FLAT_ONE_CREDIT_MODELS:
        return inputs  # flat 1 credit per output — nothing to clamp
    budget = _budget_for(model_name)
    capped = dict(inputs)
    capped["generation_mode"] = budget.generation_mode
    capped["resolution"] = budget.resolution
    if "num_images" in capped:
        capped["num_images"] = 1
    capped.pop("face_reference", None)
    capped.pop("face_image", None)
    return capped


class FashnTryOnProvider(TryOnProvider):
    name = "fashn"

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = "https://api.fashn.ai",
        model: str = "tryon-v1.6",
        client: httpx.AsyncClient | None = None,
        poll_interval: float = 2.0,
        timeout_s: float = 180.0,
        mode: str = "quality",
    ) -> None:
        self._api_key = api_key
        self._base = base_url.rstrip("/")
        self._model = model
        self._client = client
        self._poll_interval = poll_interval
        self._timeout_s = timeout_s
        self._mode = mode

    @property
    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._api_key}", "Content-Type": "application/json"}

    async def _run_outputs(self, model_name: str, inputs: dict) -> list[str]:
        """Submit ONE FASHN job on the universal /v1/run endpoint and poll to a
        terminal state, returning ALL output image URLs. This is the single code
        path every FASHN capability shares (try-on, edit, product-to-model,
        model-create) — one provider, one key (§11), routed by ``model_name``.
        Errors map to TryOnInputError (permanent) / TryOnTransientError (retryable)
        / TimeoutError exactly as before."""
        # HARD SPEND CAP (§14): clamp to the ≤1-credit configuration and refuse
        # to submit anything the pricing table still prices above the cap —
        # blocked BEFORE FASHN sees it, so no external credit can be spent.
        inputs = _capped_inputs(model_name, inputs)
        estimated = fashn_estimated_credits(model_name, inputs)
        if estimated > _budget_for(model_name).max_credits:
            log.error(
                "FASHN request blocked by spend cap: model=%s estimated=%d cr (budget=%d)",
                model_name,
                estimated,
                _budget_for(model_name).max_credits,
            )
            raise TryOnInputError(
                "This render mode isn't available right now. Please try the standard mode instead."
            )
        client = self._client or httpx.AsyncClient(timeout=30.0)
        owns_client = self._client is None
        try:
            try:
                run = await client.post(
                    f"{self._base}/v1/run",
                    headers=self._headers,
                    json={"model_name": model_name, "inputs": inputs},
                )
                run.raise_for_status()
            except httpx.HTTPStatusError as exc:
                raise _classify_http_error(exc) from exc
            except httpx.RequestError as exc:  # connect/read/transport blip — retry
                raise TryOnTransientError(f"FASHN request error: {exc}") from exc
            run_data = run.json()
            job_id = run_data.get("id")
            if not job_id:
                raise TryOnTransientError(f"FASHN run returned no id: {run_data.get('error')}")
            log.info("FASHN run %s submitted (model=%s)", job_id, model_name)

            deadline = time.monotonic() + self._timeout_s
            while True:
                try:
                    status_resp = await client.get(
                        f"{self._base}/v1/status/{job_id}", headers=self._headers
                    )
                    status_resp.raise_for_status()
                except httpx.HTTPStatusError as exc:
                    raise _classify_http_error(exc) from exc
                except httpx.RequestError as exc:
                    raise TryOnTransientError(f"FASHN status error: {exc}") from exc
                data = status_resp.json()
                status = data.get("status")
                log.debug("FASHN run %s status=%s", job_id, status)
                if status == _TERMINAL_OK:
                    output = data.get("output") or []
                    if not output:
                        # Completed but empty — almost always transient; retry.
                        raise TryOnTransientError("FASHN completed with no output")
                    log.info("FASHN run %s completed (%d image(s))", job_id, len(output))
                    return list(output)
                if status in _TERMINAL_FAIL:
                    error = data.get("error")
                    name = error.get("name") if isinstance(error, dict) else None
                    # Log the raw name/payload (never PII) for diagnosis; the user
                    # only ever sees the mapped friendly sentence (CLAUDE.md §14).
                    log.warning(
                        "FASHN run %s ended status=%s name=%s error=%s",
                        job_id,
                        status,
                        name,
                        error,
                    )
                    if isinstance(name, str) and name in _PERMANENT_ERRORS:
                        # User's input won't change on retry — fail fast, friendly.
                        raise TryOnInputError(_FRIENDLY_ERRORS[name])
                    # Generic/unknown terminal failure — usually transient; retry.
                    raise TryOnTransientError(_friendly_fashn_error(error))
                if time.monotonic() > deadline:
                    log.warning(
                        "FASHN run %s timed out after %ss (last status=%s)",
                        job_id,
                        self._timeout_s,
                        status,
                    )
                    # Already waited the full ceiling — don't retry (too slow); the
                    # worker surfaces a clean message.
                    raise TimeoutError("FASHN run timed out")
                await asyncio.sleep(self._poll_interval)
        finally:
            if owns_client:
                await client.aclose()

    async def _run(self, model_name: str, inputs: dict) -> str:
        """Run a FASHN model and return the FIRST output URL (the single-image case)."""
        outputs = await self._run_outputs(model_name, inputs)
        return outputs[0]

    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        # Virtual Try-On (tryon-v1.6) is a FLAT 1 credit per output at ANY
        # `mode`, so best-quality rendering stays within the spend cap
        # (CLAUDE.md §1 quality-first; §14 cost control).
        return await self._run(
            self._model,
            {
                "model_image": person_image_url,
                "garment_image": garment_image_url,
                "category": "auto",
                "mode": self._mode,
            },
        )

    async def edit_image(self, *, image: str, prompt: str) -> str:
        """FASHN **Edit** (model_name='edit') — used for AI Enhance Item (FASHN has
        no dedicated Packshot API model, so Edit is the fallback per spec). ``image``
        is a URL or a base64 data URI; the prompt is product-preserving. Runs at
        **balanced·1k** = 2 external credits — the premium <=2-credit Edit setting
        that restores the old quality (the `edit` budget in `_GEN_BUDGET` enforces
        this centrally; fast·1k looked degraded)."""
        return await self._run(
            "edit",
            {
                "image": image,
                "prompt": prompt,
                "generation_mode": "balanced",
                "resolution": "1k",
                "output_format": "png",
            },
        )

    async def product_to_model(
        self,
        *,
        product_image: str,
        prompt: str,
        aspect_ratio: str = "3:4",
    ) -> str:
        """FASHN **Product to Model** (model_name='product-to-model') — used for the
        Catalog Model Shot. Puts the garment on an AI fashion model from the product
        image alone; NO studio preset image is required. Runs at fast·1k — the only
        ≤1-credit configuration (enforced centrally); Pro Max HD keeps its app-side
        pricing but never raises the FASHN spend."""
        return await self._run(
            "product-to-model",
            {
                "product_image": product_image,
                "prompt": prompt,
                "aspect_ratio": aspect_ratio,
                "resolution": "1k",
                "generation_mode": "fast",
                "output_format": "png",
            },
        )

    async def model_create(
        self,
        *,
        prompt: str,
        num_images: int = 1,
        seed: int = 42,
        aspect_ratio: str = "3:4",
    ) -> list[str]:
        """FASHN **Model Create** (model_name='model-create') — used by the offline
        mannequin-candidate generator (admin script). The spend cap pins it to
        fast·1k·ONE image per call (1 credit); run it N times for N candidates."""
        return await self._run_outputs(
            "model-create",
            {
                "prompt": prompt,
                "num_images": max(1, min(4, num_images)),  # clamped to 1 centrally
                "seed": seed,
                "aspect_ratio": aspect_ratio,
                "resolution": "1k",
                "generation_mode": "fast",
                "output_format": "png",
            },
        )
