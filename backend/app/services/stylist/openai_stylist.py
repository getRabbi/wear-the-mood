"""OpenAI stylist (CLAUDE.md §2.1) — the GPT fallback for Claude.

Reuses the Anthropic stylist's prompt + JSON parsing; only the API call differs.
Token usage rides back for cost logging (§14).
"""

from __future__ import annotations

from app.services.llm.routing import openai_chat_json
from app.services.stylist.anthropic_stylist import _SYSTEM, _extract_json, build_prompt
from app.services.stylist.base import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
)
from app.services.weather import WeatherSnapshot


class OpenAIStylist(StylistProvider):
    name = "openai"

    def __init__(self, api_key: str, model: str) -> None:
        self._api_key = api_key
        self._model = model

    async def suggest(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: StylistContext,
    ) -> StylistSuggestion:
        text, in_tok, out_tok = await openai_chat_json(
            self._api_key,
            self._model,
            _SYSTEM,
            build_prompt(wardrobe, weather, context),
            max_tokens=400,
        )
        data = _extract_json(text)
        return StylistSuggestion(
            item_ids=[str(i) for i in (data.get("item_ids") or [])],
            title=str(data.get("title") or "Today's look"),
            rationale=str(data.get("rationale") or ""),
            input_tokens=in_tok,
            output_tokens=out_tok,
        )
