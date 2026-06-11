"""Stub stylist — deterministic, no key, no network.

Keeps the daily-suggestion loop runnable without an LLM, and serves as the
graceful fallback when the real provider fails (§2.1). Picks a simple, sensible
outfit (a top + a bottom, plus a layer when it's cool) and writes a short,
weather-aware rationale.
"""

from __future__ import annotations

from app.services.stylist.base import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
)
from app.services.weather import WeatherSnapshot

_COOL_C = 18.0  # add a layer at or below this temperature


def _first_in(wardrobe: list[WardrobeBrief], *categories: str) -> WardrobeBrief | None:
    wanted = {c.lower() for c in categories}
    for item in wardrobe:
        if (item.category or "").lower() in wanted:
            return item
    return None


class StubStylist(StylistProvider):
    name = "stub"

    async def suggest(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: StylistContext,
    ) -> StylistSuggestion:
        if not wardrobe:
            return StylistSuggestion(
                title="Your closet is empty",
                rationale="Add a few pieces and I'll put an outfit together for you.",
            )

        picks: list[WardrobeBrief] = []
        for item in (_first_in(wardrobe, "Tops", "Dresses"), _first_in(wardrobe, "Bottoms")):
            if item is not None:
                picks.append(item)

        cool = weather is not None and (weather.feels_like_c or weather.temp_c) <= _COOL_C
        if cool:
            layer = _first_in(wardrobe, "Outerwear")
            if layer is not None:
                picks.append(layer)

        if not picks:  # no recognizable categories — just take the first item
            picks = wardrobe[:1]

        if weather is not None:
            rationale = f"{weather.summary()} — an easy, comfortable outfit" + (
                " with a layer to stay warm." if cool else "."
            )
        else:
            rationale = "A simple, versatile outfit from your closet."

        return StylistSuggestion(
            item_ids=[i.id for i in picks],
            title="Everyday look",
            rationale=rationale,
        )
