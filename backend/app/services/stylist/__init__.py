from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.stylist.base import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
)
from app.services.stylist.stub import StubStylist

__all__ = [
    "StylistContext",
    "StylistProvider",
    "StylistSuggestion",
    "WardrobeBrief",
    "get_stylist_provider",
]


@lru_cache
def get_stylist_provider() -> StylistProvider:
    """Resolve the stylist (CLAUDE.md §2.1). Claude Sonnet when an Anthropic key
    is set; the deterministic stub otherwise (CI/api/local without a key). The
    stub also backs the router's graceful fallback when the LLM fails."""
    settings = get_settings()
    if is_secret_set(settings.anthropic_api_key):
        from app.services.stylist.anthropic_stylist import AnthropicStylist

        return AnthropicStylist(settings.anthropic_api_key, settings.anthropic_model_stylist)
    return StubStylist()
