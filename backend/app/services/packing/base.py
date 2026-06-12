"""Packing planner interfaces (CLAUDE.md §24).

A "stylist for a trip": given the user's wardrobe + trip length + weather, produce
a packing list (item ids). Providers go behind PackingProvider; the stub is a
deterministic heuristic so it works with no AI key, and AnthropicPacker curates
with Claude when a key is present. Reuses the stylist's WardrobeBrief + weather.
"""

from __future__ import annotations

import math
from abc import ABC, abstractmethod

from pydantic import BaseModel

from app.services.stylist import WardrobeBrief
from app.services.weather import WeatherSnapshot

# Category order + how the heuristic scales each with trip length.
ESSENTIAL_ORDER = ["tops", "bottoms", "outerwear", "shoes", "dresses", "accessories"]

# Below this feels-like temperature we pack a layer (§2 weather context).
COOL_FEELS_LIKE_C = 16.0


class PackingContext(BaseModel):
    days: int
    occasion: str | None = None
    note: str | None = None


class PackingList(BaseModel):
    """A provider's packing result; token usage rides back for cost logging (§14)."""

    item_ids: list[str]
    title: str
    notes: str
    input_tokens: int | None = None
    output_tokens: int | None = None


class PackingProvider(ABC):
    name: str

    @abstractmethod
    async def plan(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: PackingContext,
    ) -> PackingList:
        """Return a packing list for the trip, or raise."""
        raise NotImplementedError


def plan_counts(days: int, *, want_outerwear: bool) -> dict[str, int]:
    """How many of each category to pack for a `days`-long trip. Pure + tested."""
    return {
        "tops": max(2, math.ceil(days * 0.7)),
        "bottoms": max(1, math.ceil(days / 2)),
        "outerwear": 1 if want_outerwear else 0,
        "shoes": 2,
        "dresses": 1,
        "accessories": 2,
    }
