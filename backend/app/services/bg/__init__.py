from functools import lru_cache

from app.core.config import get_settings
from app.services.bg.base import BackgroundRemovalResult, BackgroundRemover
from app.services.bg.stub import StubBackgroundRemover

__all__ = [
    "BackgroundRemover",
    "BackgroundRemovalResult",
    "get_background_remover",
    "prewarm_background_remover",
]


@lru_cache
def get_background_remover() -> BackgroundRemover:
    """Resolve the active background remover (CLAUDE.md §2.2). Env-routed via
    BG_PROVIDER: 'rembg' on the worker (heavy model, lazy-imported so nothing else
    pulls onnxruntime), 'stub' everywhere else (CI/api/local)."""
    if get_settings().bg_provider.lower() == "rembg":
        from app.services.bg.rembg_remover import RembgBackgroundRemover

        return RembgBackgroundRemover()
    return StubBackgroundRemover()


def prewarm_background_remover() -> BackgroundRemover:
    """Construct (and cache) the remover BEFORE a dedicated cutout worker enters
    its claim loop, so a model that cannot load fails the worker up front instead
    of stranding claimed items in 'processing' (§ BG upgrade §8). Raises on a real
    model-initialization failure. process_cutout is the additional safety net for
    the combined DO worker, which also runs try-on/AI and must not exit on a bg
    model fault."""
    return get_background_remover()
