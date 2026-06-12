import logging
from functools import lru_cache

from app.core.config import get_settings
from app.services.llm.routing import provider_order
from app.services.stylist.base import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
)
from app.services.stylist.stub import StubStylist

log = logging.getLogger("fashionos.stylist")

__all__ = [
    "StylistContext",
    "StylistProvider",
    "StylistSuggestion",
    "WardrobeBrief",
    "get_stylist_provider",
]


class _FallbackStylist(StylistProvider):
    """Try each backend in order (primary first, the other as fallback, §2.1);
    first success wins, else the last error propagates so the router's stub
    fallback takes over."""

    def __init__(self, backends: list[StylistProvider]) -> None:
        self._backends = backends
        self.name = "+".join(b.name for b in backends)

    async def suggest(self, *, wardrobe, weather, context) -> StylistSuggestion:
        last: Exception | None = None
        for backend in self._backends:
            try:
                return await backend.suggest(wardrobe=wardrobe, weather=weather, context=context)
            except Exception as exc:  # try the next backend
                last = exc
                log.warning("stylist backend %s failed: %s", backend.name, exc)
        raise last if last else RuntimeError("no stylist backend")


@lru_cache
def get_stylist_provider() -> StylistProvider:
    """Resolve the stylist (CLAUDE.md §2.1): Claude and/or GPT by key + LLM_PRIMARY
    (the non-leading one is the automatic fallback), stub when neither key is set.
    The stub also backs the router's graceful fallback when every LLM fails."""
    settings = get_settings()
    backends: list[StylistProvider] = []
    for name in provider_order():
        if name == "anthropic":
            from app.services.stylist.anthropic_stylist import AnthropicStylist

            backends.append(
                AnthropicStylist(settings.anthropic_api_key, settings.anthropic_model_stylist)
            )
        else:
            from app.services.stylist.openai_stylist import OpenAIStylist

            backends.append(OpenAIStylist(settings.openai_api_key, settings.openai_model_chat))
    if not backends:
        return StubStylist()
    return backends[0] if len(backends) == 1 else _FallbackStylist(backends)
