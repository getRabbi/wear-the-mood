"""Try-on input moderation (§19) — stub + routing + decision logic (no network)."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest

from app.core.config import get_settings
from app.services.moderation import get_moderator
from app.services.moderation.base import Moderator
from app.services.moderation.openai_moderator import OpenAIModerator, decide
from app.services.moderation.stub import StubModerator


@pytest.fixture(autouse=True)
def _clear_cache():
    get_moderator.cache_clear()
    get_settings.cache_clear()
    yield
    get_moderator.cache_clear()
    get_settings.cache_clear()


def test_default_moderator_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "")  # ignore any real key in a local .env
    get_settings.cache_clear()
    get_moderator.cache_clear()
    moderator = get_moderator()
    assert isinstance(moderator, Moderator)
    assert moderator.name == "stub"


def test_stub_allows_everything() -> None:
    result = asyncio.run(StubModerator().check_image("https://x/any.jpg"))
    assert result.allowed is True


def test_routes_to_openai_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "sk-realish-key")
    get_settings.cache_clear()
    get_moderator.cache_clear()
    assert get_moderator().name == "openai"


def test_decide_blocks_flagged_categories() -> None:
    flagged = SimpleNamespace(sexual=False, sexual_minors=False, violence_graphic=True)
    result = decide(flagged)
    assert result.allowed is False
    assert "violence_graphic" in (result.reason or "")


def test_decide_allows_clean() -> None:
    clean = SimpleNamespace(sexual=False, sexual_minors=False, violence_graphic=False)
    assert decide(clean).allowed is True


def test_openai_moderator_blocks_via_injected_client() -> None:
    categories = SimpleNamespace(sexual=True, sexual_minors=False, violence_graphic=False)

    class _Moderations:
        async def create(self, **kwargs):
            return SimpleNamespace(results=[SimpleNamespace(categories=categories)])

    client = SimpleNamespace(moderations=_Moderations())
    moderator = OpenAIModerator("k", "omni-moderation-latest", client=client)
    result = asyncio.run(moderator.check_image("https://x/img.jpg"))
    assert result.allowed is False
    assert "sexual" in (result.reason or "")
