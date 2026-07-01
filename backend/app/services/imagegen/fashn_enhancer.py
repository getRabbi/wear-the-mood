"""FASHN-backed AI Enhance (BUILD_PROMPT_PRO_PROMAX.md — AI Enhance Item).

FASHN has NO dedicated Packshot API model, so per the provider strategy this uses
FASHN **Edit** (model_name='edit') with a conservative, product-preserving prompt.
Implements the existing :class:`ImageEnhancer` interface (bytes → bytes) so the
worker path is unchanged: it hands us the item's image bytes; we inline them as a
base64 data URI (never proxy a private URL that could expire, §8/§11), run Edit,
download the result and return the enhanced bytes. FASHN failures propagate as
TryOnError, so the worker fails the job cleanly and refunds — never fakes success.
"""

from __future__ import annotations

from base64 import b64encode

from app.services.imagegen.base import ImageEnhancer
from app.services.storage import download_image
from app.services.tryon.fashn import FashnTryOnProvider

# Conservative product-preserving prompt (verbatim from the provider strategy).
ENHANCE_PROMPT = (
    "Create a clean catalog-ready product image of this clothing item. "
    "Preserve the garment shape, color, texture, logo, stitching and pattern as "
    "much as possible. Improve lighting, sharpness and presentation. Do not invent "
    "new garment details. Do not change the product design. Use a clean studio "
    "product-photo look."
)


class FashnImageEnhancer(ImageEnhancer):
    name = "fashn"

    def __init__(self, provider: FashnTryOnProvider) -> None:
        # Reuses the single configured FASHN provider (one key, backend-only, §11).
        self._provider = provider

    async def enhance(self, image: bytes, *, content_type: str = "image/png") -> bytes:
        data_uri = f"data:{content_type};base64,{b64encode(image).decode('ascii')}"
        output_url = await self._provider.edit_image(
            image=data_uri, prompt=ENHANCE_PROMPT
        )
        return await download_image(output_url)
