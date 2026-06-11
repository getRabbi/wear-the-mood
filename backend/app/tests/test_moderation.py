"""Try-on input moderation (§19) — stub + routing + decision logic (no network)."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest

from app.core.config import get_settings
from app.services.moderation import get_moderator
from app.services.moderation.base import Moderator
from app.services.moderation.openai_moderator import (
    _TEXT_BLOCK_CATEGORIES,
    OpenAIModerator,
    decide,
)
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
    assert asyncio.run(StubModerator().check_image("https://x/any.jpg")).allowed
    assert asyncio.run(StubModerator().check_text("anything goes")).allowed


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


def test_decide_text_blocks_hate_but_image_set_ignores_it() -> None:
    # 'hate' blocks UGC text but is not in the (stricter-scoped) image set.
    cats = SimpleNamespace(hate=True, sexual=False, violence_graphic=False)
    assert decide(cats, _TEXT_BLOCK_CATEGORIES).allowed is False
    assert decide(cats).allowed is True  # default = image categories


def test_openai_moderator_check_text_blocks_via_injected_client() -> None:
    categories = SimpleNamespace(hate=True)

    class _Moderations:
        async def create(self, **kwargs):
            return SimpleNamespace(results=[SimpleNamespace(categories=categories)])

    moderator = OpenAIModerator(
        "k", "omni-moderation-latest", client=SimpleNamespace(moderations=_Moderations())
    )
    result = asyncio.run(moderator.check_text("something hateful"))
    assert result.allowed is False
    assert "hate" in (result.reason or "")
