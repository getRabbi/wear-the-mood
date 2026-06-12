"""Packing planner (CLAUDE.md §24). Resolve the provider: Claude when an Anthropic
key is set (reusing the stylist model), else the deterministic stub heuristic."""

from __future__ import annotations

from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.packing.base import (
    PackingContext,
    PackingList,
    PackingProvider,
    plan_counts,
)
from app.services.packing.stub import StubPacker

__all__ = [
    "PackingContext",
    "PackingList",
    "PackingProvider",
    "StubPacker",
    "get_packing_provider",
    "plan_counts",
]


@lru_cache
def get_packing_provider() -> PackingProvider:
    settings = get_settings()
    if is_secret_set(settings.anthropic_api_key):
        from app.services.packing.anthropic_packer import AnthropicPacker

        return AnthropicPacker(settings.anthropic_api_key, settings.anthropic_model_stylist)
    return StubPacker()
