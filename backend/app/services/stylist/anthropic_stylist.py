"""Claude stylist (CLAUDE.md §2.1) — nuanced "what do I wear today?".

Claude Sonnet reasons over the user's wardrobe + weather + occasion and returns
compact JSON naming the item ids to wear. Token usage rides back for cost logging
(§14). The api process needs the anthropic SDK (now a base dependency); a client
can be injected so tests need no SDK and no network.
"""

from __future__ import annotations

import json

from app.services.stylist.base import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
)
from app.services.weather import WeatherSnapshot

_SYSTEM = (
    "You are a personal fashion stylist. Given a user's wardrobe (each line is "
    "'[id] description (category)'), today's weather, and any occasion or note, "
    "choose ONE cohesive outfit using ONLY items from their wardrobe. Reply with "
    "ONLY compact JSON (no prose, no markdown) with keys: "
    "item_ids (array of the chosen item ids, copied exactly from the wardrobe), "
    "title (a short outfit name), "
    "rationale (1-2 sentences on why it suits the weather/occasion). "
    "Pick 2-4 items that work together (e.g. a top and a bottom; add outerwear "
    "when it's cold). Items marked ★ match the user's taste — prefer them when "
    "they fit. Never invent ids that are not in the wardrobe."
)


def _extract_json(text: str) -> dict:
    text = text.strip()
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        return {}
    try:
        parsed = json.loads(text[start : end + 1])
    except (ValueError, TypeError):
        return {}
    return parsed if isinstance(parsed, dict) else {}


def build_prompt(
    wardrobe: list[WardrobeBrief],
    weather: WeatherSnapshot | None,
    context: StylistContext,
) -> str:
    lines = ["Wardrobe:"]
    lines += [f"- {item.label()}" for item in wardrobe]
    lines += ["", f"Weather: {weather.summary() if weather else 'unknown'}"]
    if context.occasion:
        lines.append(f"Occasion: {context.occasion}")
    if context.note:
        lines.append(f"Note: {context.note}")
    lines += ["", "Pick today's outfit as JSON."]
    return "\n".join(lines)


class AnthropicStylist(StylistProvider):
    name = "anthropic"

    def __init__(self, api_key: str, model: str, *, client: object | None = None) -> None:
        if client is not None:
            self._client = client
        else:
            from anthropic import AsyncAnthropic

            self._client = AsyncAnthropic(api_key=api_key)
        self._model = model

    async def suggest(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: StylistContext,
    ) -> StylistSuggestion:
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=400,
            system=_SYSTEM,
            messages=[{"role": "user", "content": build_prompt(wardrobe, weather, context)}],
        )
        text = "".join(block.text for block in msg.content if block.type == "text")
        data = _extract_json(text)
        return StylistSuggestion(
            item_ids=[str(i) for i in (data.get("item_ids") or [])],
            title=str(data.get("title") or "Today's look"),
            rationale=str(data.get("rationale") or ""),
            input_tokens=msg.usage.input_tokens,
            output_tokens=msg.usage.output_tokens,
        )
