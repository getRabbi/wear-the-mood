"""rembg background remover (CLAUDE.md §2.2) — MIT, commercial-OK.

Heavy: pulls onnxruntime + a U2Net/ISNet model, so it's installed only on the
Render worker (requirements-worker.txt) and lazy-imported here. rembg is
CPU-blocking, so inference runs in a thread to keep the worker's event loop free.
Swap the session model to ISNet/BiRefNet for better edges/hair later (§2.2).
"""

from __future__ import annotations

import asyncio

from app.services.bg.base import BackgroundRemover


class RembgBackgroundRemover(BackgroundRemover):
    name = "rembg"

    def __init__(self) -> None:
        from rembg import new_session

        from app.core.config import get_settings

        # The session model is env-selected (REMBG_MODEL) so a lighter model
        # (u2netp) can cut cold-start init without a code change. Must match the
        # model BAKED into the image (the Dockerfile bakes the same name), so
        # new_session() loads from disk and never downloads at execution time.
        self._session = new_session(get_settings().rembg_model or "u2net")

    async def remove(self, image: bytes) -> bytes:
        from rembg import remove

        return await asyncio.to_thread(remove, image, session=self._session)
