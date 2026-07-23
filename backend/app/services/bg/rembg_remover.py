"""rembg background remover (CLAUDE.md §2.2) — MIT, commercial-OK.

Heavy: pulls onnxruntime + a U2Net/ISNet/BiRefNet model, so it is installed only
on the worker (requirements-worker.txt) and lazy-imported via
``get_background_remover``. rembg is CPU-blocking, so inference runs in a thread to
keep the worker's event loop free.

Two paths, selected by ``BG_MASK_PIPELINE_V2`` (§ BG upgrade §8):

  * **v2** (the upgrade): normalize the original → mask-only inference (soft alpha
    preserved: no alpha-matting, no ``post_process_mask``, no global threshold) →
    composite the soft mask onto the original → return the cutout PNG **plus** the
    editable mask PNG at the normalized dimensions.
  * **legacy** (default): the exact pre-upgrade behaviour (rembg's default
    composite), unchanged, kept purely for staged rollout / rollback — still
    through the configured session/model, but producing no separable mask.

Both paths use the SAME cached session (one model per process).
"""

from __future__ import annotations

import asyncio
import io
import logging

from app.core.config import SUPPORTED_BG_MODELS, get_settings
from app.services.bg.base import BackgroundRemovalResult, BackgroundRemover

log = logging.getLogger("fashionos.bg.rembg")


class RembgBackgroundRemover(BackgroundRemover):
    def __init__(self) -> None:
        from rembg import new_session

        settings = get_settings()
        model = settings.background_model
        if model not in SUPPORTED_BG_MODELS:
            raise ValueError(
                f"Unsupported BG_MODEL {model!r}; expected one of {sorted(SUPPORTED_BG_MODELS)}"
            )
        # One session per process — get_background_remover() is lru_cached, so the
        # model loads exactly once. It must match the model BAKED into the image
        # (the Dockerfile bakes the same name), so new_session loads from disk
        # (U2NET_HOME) and never downloads at execution time.
        self._model = model
        self._session = new_session(model)
        self._mask_pipeline_v2 = settings.bg_mask_pipeline_v2
        # remover.name carries the model for ai_usage_log + observability (§10).
        self.name = f"rembg:{model}"
        log.info("rembg remover ready model=%s mask_pipeline_v2=%s", model, self._mask_pipeline_v2)

    async def remove(self, image: bytes) -> BackgroundRemovalResult:
        if self._mask_pipeline_v2:
            return await asyncio.to_thread(self._remove_v2, image)
        return await asyncio.to_thread(self._remove_legacy, image)

    def _remove_legacy(self, image: bytes) -> BackgroundRemovalResult:
        """Pre-upgrade path: rembg's default composite, byte-for-byte unchanged.
        No separable mask is produced here (rollback-only)."""
        from rembg import remove

        cutout = remove(image, session=self._session)
        return BackgroundRemovalResult(
            cutout_png=cutout, mask_png=None, width=0, height=0, model=self._model
        )

    def _remove_v2(self, image: bytes) -> BackgroundRemovalResult:
        """Upgrade path: soft-alpha mask-only inference → composite → editable mask."""
        from rembg import remove

        from app.services.bg import imaging

        settings = get_settings()
        norm = imaging.normalize_source_image(image, max_edge=settings.bg_max_image_edge)
        size = (norm.width, norm.height)
        # MASK ONLY — keep the model's soft alpha. No alpha-matting, no generic
        # post_process_mask, no threshold (§8). Passing a PIL image returns a PIL
        # 'L' mask; be defensive about a bytes return from other rembg builds.
        raw = remove(
            norm.image,
            session=self._session,
            only_mask=True,
            alpha_matting=False,
            post_process_mask=False,
        )
        if not hasattr(raw, "size"):
            from PIL import Image

            raw = Image.open(io.BytesIO(raw))
        mask = imaging.coerce_model_mask(raw, size=size)
        cutout_png = imaging.compose_cutout_png(norm.image, mask)
        mask_png = imaging.encode_mask_png(mask)
        return BackgroundRemovalResult(
            cutout_png=cutout_png,
            mask_png=mask_png,
            width=norm.width,
            height=norm.height,
            model=self._model,
        )
