"""Claude packing planner (CLAUDE.md §24, §2.1) — curates a trip's packing list.

Lazy-imports the anthropic SDK. Asks for compact JSON (item ids the user owns +
a title + notes) and parses it tolerantly; hallucinated ids are filtered by the
router against the real wardrobe. Token usage returns for cost logging (§14).
"""

from __future__ import annotations

from app.services.packing.base import PackingContext, PackingList, PackingProvider
from app.services.stylist import WardrobeBrief
from app.services.stylist.anthropic_stylist import _extract_json
from app.services.weather import WeatherSnapshot

_SYSTEM = (
    "You are a practical travel stylist. Given a person's wardrobe, trip length, "
    "occasion and the destination weather, choose a versatile, mix-and-match "
    "packing list from ONLY the items provided. Pack light but cover the days and "
    "occasions; add a layer when it's cool. Reply with ONLY compact JSON (no prose, "
    "no markdown) with keys: item_ids (array of ids from the wardrobe), title (a "
    "short list name), notes (1-2 sentences). Never invent ids."
)


def build_prompt(
    wardrobe: list[WardrobeBrief],
    weather: WeatherSnapshot | None,
    context: PackingContext,
) -> str:
    lines = [f"Trip length: {context.days} days"]
    if context.occasion:
        lines.append(f"Occasion: {context.occasion}")
    if context.note:
        lines.append(f"Note: {context.note}")
    if weather is not None:
        lines.append(f"Destination weather: {weather.summary()}")
    lines.append("\nWardrobe:")
    lines.extend(item.label() for item in wardrobe)
    lines.append("\nReturn the packing list as JSON.")
    return "\n".join(lines)


class AnthropicPacker(PackingProvider):
    name = "anthropic"

    def __init__(self, api_key: str, model: str) -> None:
        from anthropic import AsyncAnthropic

        self._client = AsyncAnthropic(api_key=api_key)
        self._model = model

    async def plan(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: PackingContext,
    ) -> PackingList:
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=600,
            system=_SYSTEM,
            messages=[{"role": "user", "content": build_prompt(wardrobe, weather, context)}],
        )
        text = "".join(block.text for block in msg.content if block.type == "text")
        data = _extract_json(text)
        item_ids = [str(i) for i in (data.get("item_ids") or [])]
        return PackingList(
            item_ids=item_ids,
            title=str(data.get("title") or f"Packing for {context.days} days"),
            notes=str(data.get("notes") or ""),
            input_tokens=msg.usage.input_tokens,
            output_tokens=msg.usage.output_tokens,
        )
