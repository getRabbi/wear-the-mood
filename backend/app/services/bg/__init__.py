from functools import lru_cache

from app.core.config import get_settings
from app.services.bg.base import BackgroundRemover
from app.services.bg.stub import StubBackgroundRemover


@lru_cache
def get_background_remover() -> BackgroundRemover:
    """Resolve the active background remover (CLAUDE.md §2.2). Env-routed via
    BG_PROVIDER; the rembg implementation (heavy, lazy-imported, worker-only)
    lands in the next step. The stub keeps the pipeline runnable now."""
    _ = get_settings().bg_provider  # routed in the next step
    return StubBackgroundRemover()
