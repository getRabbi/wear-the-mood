"""LLM tagging service — stub + routing + JSON parsing (no key/network)."""

from __future__ import annotations

import asyncio

import pytest

from app.core.config import get_settings
from app.services.llm import get_embedder, get_garment_tagger
from app.services.llm.anthropic_tagger import _extract_json
from app.services.llm.base import Embedder, GarmentTagger
from app.services.llm.stub import StubEmbedder, StubGarmentTagger


@pytest.fixture(autouse=True)
def _clear_cache():
    get_garment_tagger.cache_clear()
    get_embedder.cache_clear()
    get_settings.cache_clear()
    yield
    get_garment_tagger.cache_clear()
    get_embedder.cache_clear()
    get_settings.cache_clear()


def test_default_tagger_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")  # ignore any real key in a local .env
    get_settings.cache_clear()
    get_garment_tagger.cache_clear()
    tagger = get_garment_tagger()
    assert isinstance(tagger, GarmentTagger)
    assert tagger.name == "stub"


def test_stub_tagger_returns_empty() -> None:
    tags = asyncio.run(StubGarmentTagger().tag(b"img", "image/png"))
    assert tags.category is None
    assert tags.tags == []


def test_anthropic_routing_lazy_imports(monkeypatch: pytest.MonkeyPatch) -> None:
    # A real key routes to Claude; the SDK is worker-only, so the lazy import
    # raises here rather than being installed in CI/api.
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-realish-key")
    get_settings.cache_clear()
    get_garment_tagger.cache_clear()
    with pytest.raises(ModuleNotFoundError):
        get_garment_tagger()


def test_placeholder_key_stays_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-xxxxxxxx")  # .env.example placeholder
    get_settings.cache_clear()
    get_garment_tagger.cache_clear()
    assert get_garment_tagger().name == "stub"


def test_default_embedder_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OPENAI_API_KEY", "")  # ignore any real key in a local .env
    get_settings.cache_clear()
    get_embedder.cache_clear()
    embedder = get_embedder()
    assert isinstance(embedder, Embedder)
    assert embedder.name == "stub"


def test_stub_embedder_returns_zero_vector() -> None:
    vec = asyncio.run(StubEmbedder().embed("white tee"))
    assert len(vec) == 1536
    assert set(vec) == {0.0}


def test_openai_routing_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    # openai is a base dep (the api embeds search queries), so a real key routes
    # to the live embedder. Constructing it does not call the network.
    monkeypatch.setenv("OPENAI_API_KEY", "sk-realish-key")
    get_settings.cache_clear()
    get_embedder.cache_clear()
    assert get_embedder().name == "openai"


def test_extract_json_tolerates_prose_and_fences() -> None:
    assert _extract_json('```json\n{"color": "red", "tags": ["a"]}\n```') == {
        "color": "red",
        "tags": ["a"],
    }
    assert _extract_json("Here you go: {\"category\": \"Tops\"} cheers") == {
        "category": "Tops"
    }
    assert _extract_json("not json") == {}
