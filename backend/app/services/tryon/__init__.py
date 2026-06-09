from functools import lru_cache

from app.services.tryon.base import TryOnProvider
from app.services.tryon.stub import StubTryOnProvider


@lru_cache
def get_tryon_provider() -> TryOnProvider:
    """Resolve the active try-on provider. Env-routed to FASHN.ai at launch
    (CLAUDE.md §2.2) in a later step; the stub keeps the lifecycle runnable now."""
    return StubTryOnProvider()
