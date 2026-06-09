from __future__ import annotations

from app.services.tryon.base import TryOnProvider


class StubTryOnProvider(TryOnProvider):
    """Placeholder provider used until FASHN.ai is wired (CLAUDE.md §2.2). Echoes
    the person image back as the 'result' so the job lifecycle can be exercised
    end-to-end without a paid API."""

    name = "stub"

    async def generate(self, *, person_image_url: str, garment_image_url: str) -> str:
        return person_image_url
