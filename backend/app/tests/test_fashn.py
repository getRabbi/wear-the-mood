"""FASHN try-on provider — mocked HTTP (no network, no key needed)."""

from __future__ import annotations

import asyncio

import httpx
import pytest

from app.core.config import get_settings
from app.services.tryon import get_tryon_provider
from app.services.tryon.fashn import FashnTryOnProvider


@pytest.fixture(autouse=True)
def _clear_cache():
    get_tryon_provider.cache_clear()
    get_settings.cache_clear()
    yield
    get_tryon_provider.cache_clear()
    get_settings.cache_clear()


def _provider(handler) -> FashnTryOnProvider:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return FashnTryOnProvider("test-key", client=client, poll_interval=0.0)


def test_completed_run_returns_output_url() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/run":
            assert request.headers["Authorization"] == "Bearer test-key"
            return httpx.Response(200, json={"id": "job-1", "error": None})
        return httpx.Response(
            200,
            json={"id": "job-1", "status": "completed", "output": ["https://cdn/r.png"]},
        )

    out = asyncio.run(
        _provider(handler).generate(person_image_url="p", garment_image_url="g")
    )
    assert out == "https://cdn/r.png"


def test_failed_run_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/run":
            return httpx.Response(200, json={"id": "job-2"})
        return httpx.Response(200, json={"id": "job-2", "status": "failed", "error": "nsfw"})

    with pytest.raises(RuntimeError):
        asyncio.run(_provider(handler).generate(person_image_url="p", garment_image_url="g"))


def test_run_without_id_raises() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"id": None, "error": "bad input"})

    with pytest.raises(RuntimeError):
        asyncio.run(_provider(handler).generate(person_image_url="p", garment_image_url="g"))


def test_polls_until_completed() -> None:
    calls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/run":
            return httpx.Response(200, json={"id": "job-3"})
        calls["n"] += 1
        if calls["n"] < 3:
            return httpx.Response(200, json={"id": "job-3", "status": "processing"})
        return httpx.Response(
            200, json={"id": "job-3", "status": "completed", "output": ["https://cdn/done.png"]}
        )

    out = asyncio.run(
        _provider(handler).generate(person_image_url="p", garment_image_url="g")
    )
    assert out == "https://cdn/done.png"
    assert calls["n"] == 3


# ── routing ──────────────────────────────────────────────────────────────────


def test_routes_to_stub_without_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TRYON_PROVIDER", "fashn")
    monkeypatch.delenv("FASHN_API_KEY", raising=False)
    get_settings.cache_clear()
    get_tryon_provider.cache_clear()
    assert get_tryon_provider().name == "stub"


def test_routes_to_fashn_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TRYON_PROVIDER", "fashn")
    monkeypatch.setenv("FASHN_API_KEY", "k")
    get_settings.cache_clear()
    get_tryon_provider.cache_clear()
    assert get_tryon_provider().name == "fashn"
