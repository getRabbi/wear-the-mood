from __future__ import annotations

from app.services.bg.base import BackgroundRemovalResult, BackgroundRemover


class StubBackgroundRemover(BackgroundRemover):
    """Placeholder remover used until rembg is wired on the worker (CLAUDE.md
    §2.2). Echoes the input bytes back as the 'cutout' so the pipeline runs
    end-to-end without the heavy model. Deliberately imports NEITHER Pillow NOR
    rembg, so the api / cron / CI stay lightweight — it therefore can't decode the
    image and reports no mask and zero dimensions. Real removal is
    RembgBackgroundRemover."""

    name = "stub"

    async def remove(self, image: bytes) -> BackgroundRemovalResult:
        return BackgroundRemovalResult(
            cutout_png=image, mask_png=None, width=0, height=0, model="stub"
        )
