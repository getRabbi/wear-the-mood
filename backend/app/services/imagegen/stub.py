"""Stub image enhancer (BUILD_PROMPT_PRO_PROMAX.md — AI Enhance Item).

Default when no real enhancement provider is wired. Behaviour is gated by the
explicit `mock` flag (from IMAGEGEN_MOCK):

  * mock=False (DEFAULT / prod): raises `ImageGenNotConfigured` — the worker fails
    the job and refunds the reserved credit. NEVER fakes a successful result.
  * mock=True (DEV only): echoes the input bytes so the full enhance flow can be
    exercised locally/CI without a paid provider.
"""

from __future__ import annotations

from app.services.imagegen.base import ImageEnhancer, ImageGenNotConfigured


class StubImageEnhancer(ImageEnhancer):
    name = "stub"

    def __init__(self, *, mock: bool = False) -> None:
        self._mock = mock

    async def enhance(self, image: bytes, *, content_type: str = "image/png") -> bytes:
        if not self._mock:
            raise ImageGenNotConfigured(
                "AI Enhance isn't available yet. Your item was added with a clean "
                "background-removed image."
            )
        return image  # dev/CI passthrough — explicitly behind IMAGEGEN_MOCK
