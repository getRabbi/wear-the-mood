from functools import lru_cache

from app.core.config import get_settings
from app.services.bg.base import BackgroundRemover
from app.services.bg.stub import StubBackgroundRemover


@lru_cache
def get_background_remover() -> BackgroundRemover:
    """Resolve the active background remover (CLAUDE.md §2.2). Env-routed via
    BG_PROVIDER: 'rembg' on the Render worker (heavy model, lazy-imported so
    nothing else pulls onnxruntime), 'stub' everywhere else (CI/api/local)."""
    if get_settings().bg_provider.lower() == "rembg":
        from app.services.bg.rembg_remover import RembgBackgroundRemover

        return RembgBackgroundRemover()
    return StubBackgroundRemover()
