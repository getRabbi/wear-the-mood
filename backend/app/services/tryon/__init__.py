from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.tryon.base import TryOnProvider
from app.services.tryon.stub import StubTryOnProvider


@lru_cache
def get_tryon_provider() -> TryOnProvider:
    """Resolve the active try-on provider (CLAUDE.md §2.2). Routes to FASHN.ai
    only when TRYON_PROVIDER=fashn AND a real key is configured; otherwise the
    stub keeps the lifecycle runnable (CI/local without a paid key)."""
    settings = get_settings()
    if settings.tryon_provider.lower() == "fashn" and is_secret_set(settings.fashn_api_key):
        from app.services.tryon.fashn import FashnTryOnProvider

        return FashnTryOnProvider(
            settings.fashn_api_key,
            base_url=settings.fashn_base_url,
            model=settings.fashn_model,
        )
    return StubTryOnProvider()
