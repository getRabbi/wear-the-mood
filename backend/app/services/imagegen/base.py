"""ImageEnhancer interface (BUILD_PROMPT_PRO_PROMAX.md — AI Enhance Item).

AI Enhance turns a flat garment photo into a clean, sharp, catalog-ready image.
All enhancement goes through this interface — never call a model/SDK directly
from a router or worker. The concrete enhancer is chosen by env in
`app.services.imagegen.get_image_enhancer`.

There is NO commercial enhancement provider wired yet (FASHN does try-on, not
flat-garment enhancement), so the default stub raises `ImageGenNotConfigured`
in production — the worker fails the job with a clean message and refunds the
reserved credit. NO fake successful output is ever produced in prod (CLAUDE.md
§25: never fake AI success).
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class ImageGenError(RuntimeError):
    """Base for image-enhancement provider failures."""


class ImageGenNotConfigured(ImageGenError):
    """No enhancement provider is configured. The worker fails the job and refunds
    the reserved credit; the user sees a clean "not available yet" message — never
    a fabricated result (CLAUDE.md §25)."""


class ImageEnhancer(ABC):
    name: str

    @abstractmethod
    async def enhance(self, image: bytes, *, content_type: str = "image/png") -> bytes:
        """Return enhanced image bytes for `image`, or raise. Raises
        `ImageGenNotConfigured` when no real provider is available."""
        raise NotImplementedError
