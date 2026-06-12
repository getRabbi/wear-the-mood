"""OpenAI news summarizer (CLAUDE.md §2.1) — the GPT fallback for Claude Haiku.

Reuses the Anthropic summarizer's system prompt; only the API call differs.
"""

from __future__ import annotations

from app.services.llm.routing import openai_chat_json
from app.services.news.anthropic_summarizer import _SYSTEM
from app.services.news.base import NewsSummarizer, NewsSummary


class OpenAISummarizer(NewsSummarizer):
    name = "openai"

    def __init__(self, api_key: str, model: str) -> None:
        self._api_key = api_key
        self._model = model

    async def summarize(self, title: str, content: str) -> NewsSummary:
        text, in_tok, out_tok = await openai_chat_json(
            self._api_key,
            self._model,
            _SYSTEM,
            f"Title: {title}\n\nArticle:\n{content}".strip(),
            max_tokens=160,
        )
        return NewsSummary(summary=text.strip(), input_tokens=in_tok, output_tokens=out_tok)
