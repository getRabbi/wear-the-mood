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


class Moderator(ABC):
    name: str

    @abstractmethod
    async def check_image(self, image_url: str) -> ModerationResult:
        """Decide whether an image is acceptable for try-on, or raise."""
        raise NotImplementedError
