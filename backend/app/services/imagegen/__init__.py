from functools import lru_cache

from app.core.config import get_settings
from app.services.imagegen.base import ImageEnhancer
from app.services.imagegen.stub import StubImageEnhancer
from app.services.tryon import get_tryon_provider
from app.services.tryon.fashn import FashnTryOnProvider


@lru_cache
def get_image_enhancer() -> ImageEnhancer:
    """Resolve the active AI Studio image enhancer (BUILD_PROMPT_PRO_PROMAX.md —
    AI Enhance Item). Single provider = FASHN: when FASHN is configured we return a
    FASHN-backed enhancer that uses FASHN **Edit** (there is no dedicated Packshot
    API model). Otherwise the stub is returned: in prod it raises
    `ImageGenNotConfigured` (mapped to PROVIDER_ERROR, never a fake result); set
    IMAGEGEN_MOCK=true in DEV to make it echo its input so the flow is exercisable.
    Never call a vendor SDK from a router — always go through this factory (§2.1)."""
    provider = get_tryon_provider()
    if isinstance(provider, FashnTryOnProvider):
        from app.services.imagegen.fashn_enhancer import FashnImageEnhancer

        return FashnImageEnhancer(provider)
    return StubImageEnhancer(mock=get_settings().imagegen_mock)
