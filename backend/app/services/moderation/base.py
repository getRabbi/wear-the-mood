"""Input/UGC moderation interface (CLAUDE.md §19).

A "put clothes on a body" tool WILL be misused — try-on input images are
moderated BEFORE any job is created, rejecting nudity/minors/graphic content.
Concrete moderators are env-routed in get_moderator; the stub allows everything
and MUST be replaced by a real moderator before public launch (launch blocker).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class ModerationResult:
    allowed: bool
    reason: str | None = None


class ModerationInputError(Exception):
    """The CALLER's image is unusable — unfetchable URL, wrong content type, too
    large, malformed. This is a client error, so the router maps it to a typed
    ``VALIDATION_ERROR`` (422), never an unhandled 500 (CLAUDE.md §13)."""


class ModerationUnavailable(Exception):
    """The moderation PROVIDER failed (5xx, timeout, rate limit, no credit).

    Callers must map this to ``PROVIDER_ERROR`` and refuse the request. It must
    NEVER fail open: §19 makes try-on input moderation mandatory, so an
    unavailable moderator means the job does not run."""


class Moderator(ABC):
    name: str

    @abstractmethod
    async def check_image(self, image_url: str) -> ModerationResult:
        """Decide whether an image is acceptable for try-on, or raise."""
        raise NotImplementedError

    @abstractmethod
    async def check_text(self, text: str) -> ModerationResult:
        """Decide whether user text (a comment/caption) is acceptable, or raise."""
        raise NotImplementedError
