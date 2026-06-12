"""Claude Haiku news summarizer (CLAUDE.md §2.1) — cheap, fast routine task.

Lazy-imports the anthropic SDK. Produces a neutral 1-2 sentence summary; token
usage rides back for cost logging (§14). Used only when an Anthropic key is set.
"""

from __future__ import annotations

from app.services.news.base import NewsSummarizer, NewsSummary

_SYSTEM = (
    "You are a fashion-news editor. Summarize the article in 1-2 neutral, "
    "factual sentences for a style app's feed. No hype, no markdown, no preamble "
    "— reply with only the summary."
)


class AnthropicSummarizer(NewsSummarizer):
    name = "anthropic"

    def __init__(self, api_key: str, model: str) -> None:
        from anthropic import AsyncAnthropic

        self._client = AsyncAnthropic(api_key=api_key)
        self._model = model

    async def summarize(self, title: str, content: str) -> NewsSummary:
        msg = await self._client.messages.create(
            model=self._model,
            max_tokens=160,
            system=_SYSTEM,
            messages=[
                {
                    "role": "user",
                    "content": f"Title: {title}\n\nArticle:\n{content}".strip(),
                }
            ],
        )
        text = "".join(block.text for block in msg.content if block.type == "text")
        return NewsSummary(
            summary=text.strip(),
            input_tokens=msg.usage.input_tokens,
            output_tokens=msg.usage.output_tokens,
        )
