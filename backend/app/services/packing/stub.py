"""Deterministic packing heuristic — the default with no AI key (CLAUDE.md §24).

Scales each clothing category by trip length and packs a layer when it's cool,
drawing only from what the user owns. Keeps the planner fully runnable + testable
without Claude, mirroring the stub stylist.
"""

from __future__ import annotations

from app.services.packing.base import (
    COOL_FEELS_LIKE_C,
    ESSENTIAL_ORDER,
    PackingContext,
    PackingList,
    PackingProvider,
    plan_counts,
)
from app.services.stylist import WardrobeBrief
from app.services.weather import WeatherSnapshot


class StubPacker(PackingProvider):
    name = "stub"

    async def plan(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: PackingContext,
    ) -> PackingList:
        # Pack a layer when it's cool, or when weather is unknown (play it safe).
        cool = weather is None or (
            weather.feels_like_c is not None and weather.feels_like_c < COOL_FEELS_LIKE_C
        )
        by_cat: dict[str, list[WardrobeBrief]] = {}
        for item in wardrobe:
            key = (item.category or "").strip().lower()
            by_cat.setdefault(key, []).append(item)

        counts = plan_counts(context.days, want_outerwear=cool)
        picked: list[str] = []
        for category in ESSENTIAL_ORDER:
            items = by_cat.get(category, [])
            picked.extend(b.id for b in items[: counts.get(category, 0)])

        day_word = "day" if context.days == 1 else "days"
        title = f"Packing for {context.days} {day_word}"
        notes = (
            f"{len(picked)} pieces for your trip"
            + (f" — {context.occasion}" if context.occasion else "")
            + (", with a layer for cooler weather" if cool else "")
            + "."
        )
        return PackingList(item_ids=picked, title=title, notes=notes)
