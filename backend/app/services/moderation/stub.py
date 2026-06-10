from __future__ import annotations

from app.services.moderation.base import ModerationResult, Moderator


class StubModerator(Moderator):
    """Allow-all placeholder (CI/local without an OpenAI key). MUST be replaced
    by a real moderator before public launch — try-on input moderation is a
    launch blocker (CLAUDE.md §19)."""

    name = "stub"

    async def check_image(self, image_url: str) -> ModerationResult:
        return ModerationResult(allowed=True)
