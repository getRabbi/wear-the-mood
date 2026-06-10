from __future__ import annotations

from app.services.bg.base import BackgroundRemover


class StubBackgroundRemover(BackgroundRemover):
    """Placeholder remover used until rembg is wired on the worker (CLAUDE.md
    §2.2). Echoes the input bytes back as the 'cutout' so the pipeline runs
    end-to-end without the heavy model. Real removal is RembgBackgroundRemover."""

    name = "stub"

    async def remove(self, image: bytes) -> bytes:
        return image
