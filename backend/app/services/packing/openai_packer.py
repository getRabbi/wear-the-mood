"""OpenAI packing planner (CLAUDE.md §2.1) — the GPT fallback for Claude.

Reuses the Anthropic packer's prompt + JSON parsing; only the API call differs.
"""

from __future__ import annotations

from app.services.llm.routing import openai_chat_json
from app.services.packing.anthropic_packer import _SYSTEM, build_prompt
from app.services.packing.base import PackingContext, PackingList, PackingProvider
from app.services.stylist import WardrobeBrief
from app.services.stylist.anthropic_stylist import _extract_json
from app.services.weather import WeatherSnapshot


class OpenAIPacker(PackingProvider):
    name = "openai"

    def __init__(self, api_key: str, model: str) -> None:
        self._api_key = api_key
        self._model = model

    async def plan(
        self,
        *,
        wardrobe: list[WardrobeBrief],
        weather: WeatherSnapshot | None,
        context: PackingContext,
    ) -> PackingList:
        text, in_tok, out_tok = await openai_chat_json(
            self._api_key,
            self._model,
            _SYSTEM,
            build_prompt(wardrobe, weather, context),
            max_tokens=600,
        )
        data = _extract_json(text)
        return PackingList(
            item_ids=[str(i) for i in (data.get("item_ids") or [])],
            title=str(data.get("title") or f"Packing for {context.days} days"),
            notes=str(data.get("notes") or ""),
            input_tokens=in_tok,
            output_tokens=out_tok,
        )
