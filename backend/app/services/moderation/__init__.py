from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.moderation.base import Moderator
from app.services.moderation.stub import StubModerator


@lru_cache
def get_moderator() -> Moderator:
    """Resolve the active moderator (CLAUDE.md §19). OpenAI omni-moderation when
    an OpenAI key is set; stub (allow-all) otherwise. The stub is a launch
    blocker — production MUST have a real moderator configured."""
    settings = get_settings()
    if is_secret_set(settings.openai_api_key):
        from app.services.moderation.openai_moderator import OpenAIModerator

        return OpenAIModerator(settings.openai_api_key, settings.openai_moderation_model)
    return StubModerator()
