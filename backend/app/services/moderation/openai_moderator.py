"""OpenAI omni-moderation image moderator (CLAUDE.md §19).

Uses the (free) Moderation endpoint with image input. Blocks a try-on input on
sexual content, minors, or graphic violence. The decision logic is split out so
it's unit-testable without the SDK.
"""

from __future__ import annotations

import logging

from app.services.moderation.base import (
    ModerationInputError,
    ModerationResult,
    ModerationUnavailable,
    Moderator,
)

log = logging.getLogger("fashionos.moderation")

# Categories that block a try-on input image (§19).
_IMAGE_BLOCK_CATEGORIES = ("sexual", "sexual_minors", "violence_graphic")

# Categories that block public UGC text (comments/captions, §19). Broader than
# the image set — hate/threats/graphic content have no place in the feed — but
# deliberately lenient on plain "harassment"/"sexual" so ordinary fashion talk
# isn't over-blocked.
_TEXT_BLOCK_CATEGORIES = (
    "sexual_minors",
    "hate",
    "hate_threatening",
    "harassment_threatening",
    "violence_graphic",
    "self_harm_intent",
    "self_harm_instructions",
)


def decide(
    categories: object, blocks: tuple[str, ...] = _IMAGE_BLOCK_CATEGORIES
) -> ModerationResult:
    blocked = [c for c in blocks if getattr(categories, c, False)]
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

    async def _create(self, payload: object, *, what: str) -> object:
        """Call the provider, translating its failures into our typed errors.

        A 400 means the provider rejected the INPUT we passed — overwhelmingly an
        image URL it could not download. That is the caller's fault, so it becomes
        ModerationInputError -> VALIDATION_ERROR rather than an unhandled 500
        (found by the Phase 5 §14.2 test). Anything else is the provider being
        unavailable, and we fail CLOSED because §19 makes moderation mandatory.
        """
        try:
            return await self._client.moderations.create(model=self._model, input=payload)
        except Exception as exc:  # noqa: BLE001 - re-raised as typed errors below
            status = getattr(exc, "status_code", None) or getattr(exc, "code", None)
            name = type(exc).__name__
            if status == 400 or name in {"BadRequestError", "UnprocessableEntityError"}:
                log.warning("moderation rejected the %s input: %s", what, exc)
                raise ModerationInputError(str(exc)) from exc
            log.error("moderation provider unavailable (%s): %s", name, exc)
            raise ModerationUnavailable(str(exc)) from exc

    async def check_image(self, image_url: str) -> ModerationResult:
        resp = await self._create(
            [{"type": "image_url", "image_url": {"url": image_url}}], what="image"
        )
        return decide(resp.results[0].categories, _IMAGE_BLOCK_CATEGORIES)

    async def check_text(self, text: str) -> ModerationResult:
        resp = await self._create([{"type": "text", "text": text}], what="text")
        return decide(resp.results[0].categories, _TEXT_BLOCK_CATEGORIES)
