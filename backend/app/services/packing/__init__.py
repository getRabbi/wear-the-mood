"""Packing planner (CLAUDE.md §24, §2.1). Resolve the provider: Claude and/or GPT
by key + LLM_PRIMARY (the other is the automatic fallback), else the stub."""

from __future__ import annotations

import logging
from functools import lru_cache

from app.core.config import get_settings
from app.services.llm.routing import provider_order
from app.services.packing.base import (
    PackingContext,
    PackingList,
    PackingProvider,
    plan_counts,
)
from app.services.packing.stub import StubPacker

log = logging.getLogger("fashionos.packing")

__all__ = [
    "PackingContext",
    "PackingList",
    "PackingProvider",
    "StubPacker",
    "get_packing_provider",
    "plan_counts",
]


class _FallbackPacker(PackingProvider):
    """Try each backend in order (primary first, the other as fallback, §2.1)."""

    def __init__(self, backends: list[PackingProvider]) -> None:
        self._backends = backends
        self.name = "+".join(b.name for b in backends)

    async def plan(self, *, wardrobe, weather, context) -> PackingList:
        last: Exception | None = None
        for backend in self._backends:
            try:
                return await backend.plan(wardrobe=wardrobe, weather=weather, context=context)
            except Exception as exc:
                last = exc
                log.warning("packing backend %s failed: %s", backend.name, exc)
        raise last if last else RuntimeError("no packing backend")


@lru_cache
def get_packing_provider() -> PackingProvider:
    settings = get_settings()
    backends: list[PackingProvider] = []
    for name in provider_order():
        if name == "anthropic":
            from app.services.packing.anthropic_packer import AnthropicPacker

            backends.append(
                AnthropicPacker(settings.anthropic_api_key, settings.anthropic_model_stylist)
            )
        else:
            from app.services.packing.openai_packer import OpenAIPacker

            backends.append(OpenAIPacker(settings.openai_api_key, settings.openai_model_chat))
    if not backends:
        return StubPacker()
    return backends[0] if len(backends) == 1 else _FallbackPacker(backends)
