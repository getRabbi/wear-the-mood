"""FASHN.ai try-on provider (CLAUDE.md §2.2) — commercial API, ~$0.075/image.

Submits a run, polls status to completion, returns the result image URL. The key
is backend-only (§11). Network/timeout/failed-run errors raise so the worker marks
the job failed and never charges (§7). Swappable for self-hosted Leffa later.
"""

from __future__ import annotations

import asyncio
import logging
import time

import httpx

from app.services.tryon.base import TryOnProvider

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


def _friendly_fashn_error(error: object) -> str:
    """Turn FASHN's `{name, message}` error into a clean, actionable sentence."""
    name = error.get("name") if isinstance(error, dict) else None
    if isinstance(name, str) and name in _FRIENDLY_ERRORS:
        return _FRIENDLY_ERRORS[name]
    return "We couldn't generate your try-on. Please try a different photo."


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

    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        client = self._client or httpx.AsyncClient(timeout=30.0)
        owns_client = self._client is None
        try:
            run = await client.post(
                f"{self._base}/v1/run",
                headers=self._headers,
                json={
                    "model_name": self._model,
                    "inputs": {
                        "model_image": person_image_url,
                        "garment_image": garment_image_url,
                        "category": "auto",
                        # Best-quality render (slower, sharper) — the founder wants
                        # the best result over speed (CLAUDE.md §1). FASHN modes:
                        # performance | balanced | quality.
                        "mode": self._mode,
                    },
                },
            )
            run.raise_for_status()
            run_data = run.json()
            job_id = run_data.get("id")
            if not job_id:
                raise RuntimeError(f"FASHN run returned no id: {run_data.get('error')}")
            log.info("FASHN run %s submitted (model=%s, mode=%s)", job_id, self._model, self._mode)

            deadline = time.monotonic() + self._timeout_s
            while True:
                status_resp = await client.get(
                    f"{self._base}/v1/status/{job_id}", headers=self._headers
                )
                status_resp.raise_for_status()
                data = status_resp.json()
                status = data.get("status")
                log.debug("FASHN run %s status=%s", job_id, status)
                if status == _TERMINAL_OK:
                    output = data.get("output") or []
                    if not output:
                        raise RuntimeError("FASHN completed with no output")
                    log.info("FASHN run %s completed", job_id)
                    return output[0]
                if status in _TERMINAL_FAIL:
                    error = data.get("error")
                    name = error.get("name") if isinstance(error, dict) else None
                    # Log the raw name/payload (never PII) for diagnosis; the user
                    # only ever sees the mapped friendly sentence (CLAUDE.md §14).
                    log.warning(
                        "FASHN run %s ended status=%s name=%s error=%s",
                        job_id, status, name, error,
                    )
                    raise RuntimeError(_friendly_fashn_error(error))
                if time.monotonic() > deadline:
                    log.warning(
                        "FASHN run %s timed out after %ss (last status=%s)",
                        job_id, self._timeout_s, status,
                    )
                    raise TimeoutError("FASHN try-on timed out")
                await asyncio.sleep(self._poll_interval)
        finally:
            if owns_client:
                await client.aclose()
