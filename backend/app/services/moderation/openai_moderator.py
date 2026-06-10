"""OpenAI omni-moderation image moderator (CLAUDE.md §19).

Uses the (free) Moderation endpoint with image input. Blocks a try-on input on
sexual content, minors, or graphic violence. The decision logic is split out so
it's unit-testable without the SDK.
"""

from __future__ import annotations

from app.services.moderation.base import ModerationResult, Moderator

# Categories that block a try-on input image (§19).
_BLOCK_CATEGORIES = ("sexual", "sexual_minors", "violence_graphic")


def decide(categories: object) -> ModerationResult:
    blocked = [c for c in _BLOCK_CATEGORIES if getattr(categories, c, False)]
    if blocked:
        return ModerationResult(allowed=False, reason=", ".join(blocked))
    return ModerationResult(allowed=True)


class OpenAIModerator(Moderator):
    name = "openai"

    def __init__(self, api_key: str, model: str, *, client: object | None = None) -> None:
        if client is not None:
            self._client = client
        else:
            from openai import AsyncOpenAI

            self._client = AsyncOpenAI(api_key=api_key)
        self._model = model

    async def check_image(self, image_url: str) -> ModerationResult:
        resp = await self._client.moderations.create(
            model=self._model,
            input=[{"type": "image_url", "image_url": {"url": image_url}}],
        )
        return decide(resp.results[0].categories)
