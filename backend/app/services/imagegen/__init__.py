from functools import lru_cache

from app.core.config import get_settings
from app.services.imagegen.base import ImageEnhancer
from app.services.imagegen.stub import StubImageEnhancer


@lru_cache
def get_image_enhancer() -> ImageEnhancer:
    """Resolve the active AI Studio image enhancer (BUILD_PROMPT_PRO_PROMAX.md —
    AI Enhance Item). No real enhancement provider is wired yet (FASHN does try-on,
    not flat-garment enhance), so the stub is returned: in prod it raises
    `ImageGenNotConfigured` (mapped to PROVIDER_ERROR, never a fake result); set
    IMAGEGEN_MOCK=true in DEV to make it echo its input so the flow is exercisable.
    Swap in a real enhancer here later — never call a vendor SDK from a router."""
    settings = get_settings()
    # Only the stub exists today; the structure mirrors get_tryon_provider so a
    # real provider slots in by name without touching callers.
    return StubImageEnhancer(mock=settings.imagegen_mock)
