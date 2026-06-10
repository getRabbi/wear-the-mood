"""FASHN.ai try-on provider (CLAUDE.md §2.2) — commercial API, ~$0.075/image.

Submits a run, polls status to completion, returns the result image URL. The key
is backend-only (§11). Network/timeout/failed-run errors raise so the worker marks
the job failed and never charges (§7). Swappable for self-hosted Leffa later.
"""

from __future__ import annotations

import asyncio
import time

import httpx

from app.services.tryon.base import TryOnProvider

_TERMINAL_OK = "completed"
_TERMINAL_FAIL = "failed"


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
        timeout_s: float = 120.0,
    ) -> None:
        self._api_key = api_key
        self._base = base_url.rstrip("/")
        self._model = model
        self._client = client
        self._poll_interval = poll_interval
        self._timeout_s = timeout_s

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
                    },
                },
            )
            run.raise_for_status()
            run_data = run.json()
            job_id = run_data.get("id")
            if not job_id:
                raise RuntimeError(f"FASHN run returned no id: {run_data.get('error')}")

            deadline = time.monotonic() + self._timeout_s
            while True:
                status_resp = await client.get(
                    f"{self._base}/v1/status/{job_id}", headers=self._headers
                )
                status_resp.raise_for_status()
                data = status_resp.json()
                status = data.get("status")
                if status == _TERMINAL_OK:
                    output = data.get("output") or []
                    if not output:
                        raise RuntimeError("FASHN completed with no output")
                    return output[0]
                if status == _TERMINAL_FAIL:
                    raise RuntimeError(f"FASHN failed: {data.get('error')}")
                if time.monotonic() > deadline:
                    raise TimeoutError("FASHN try-on timed out")
                await asyncio.sleep(self._poll_interval)
        finally:
            if owns_client:
                await client.aclose()
