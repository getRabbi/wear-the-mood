"""FASHN try-on provider — mocked HTTP (no network, no key needed)."""

from __future__ import annotations

import asyncio
import json

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

    out = asyncio.run(_provider(handler).generate(person_image_url="p", garment_image_url="g"))
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

    out = asyncio.run(_provider(handler).generate(person_image_url="p", garment_image_url="g"))
    assert out == "https://cdn/done.png"
    assert calls["n"] == 3


# ── per-feature FASHN model routing (single provider, right endpoint) ─────────


def _capturing(output, posted: dict):
    """A MockTransport handler that records the /v1/run body + returns `output`."""

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/run":
            posted.update(json.loads(request.content))
            return httpx.Response(200, json={"id": "job-x"})
        return httpx.Response(
            200, json={"id": "job-x", "status": "completed", "output": output}
        )

    return handler


def test_edit_routes_to_edit_model() -> None:
    # AI Enhance → FASHN Edit (Packshot has no distinct API model).
    posted: dict = {}
    out = asyncio.run(
        _provider(_capturing(["https://cdn/e.png"], posted)).edit_image(
            image="data:image/png;base64,QQ==", prompt="clean up"
        )
    )
    assert out == "https://cdn/e.png"
    assert posted["model_name"] == "edit"
    assert posted["inputs"]["image"] == "data:image/png;base64,QQ=="
    assert posted["inputs"]["prompt"] == "clean up"


def test_product_to_model_routes_correctly() -> None:
    # Catalog Model Shot → FASHN Product to Model (no preset image needed).
    posted: dict = {}
    out = asyncio.run(
        _provider(_capturing(["https://cdn/m.png"], posted)).product_to_model(
            product_image="data:image/png;base64,QQ==", prompt="studio", resolution="2k"
        )
    )
    assert out == "https://cdn/m.png"
    assert posted["model_name"] == "product-to-model"
    assert posted["inputs"]["product_image"] == "data:image/png;base64,QQ=="
    assert posted["inputs"]["resolution"] == "2k"


def test_model_create_returns_all_candidates() -> None:
    # Mannequin candidates → FASHN Model Create; returns EVERY output image.
    posted: dict = {}
    out = asyncio.run(
        _provider(_capturing(["u1", "u2", "u3"], posted)).model_create(
            prompt="mannequin", num_images=3
        )
    )
    assert out == ["u1", "u2", "u3"]
    assert posted["model_name"] == "model-create"
    assert posted["inputs"]["num_images"] == 3


# ── routing ──────────────────────────────────────────────────────────────────


def test_routes_to_stub_without_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TRYON_PROVIDER", "fashn")
    monkeypatch.setenv("FASHN_API_KEY", "")  # empty overrides any real .env key
    get_settings.cache_clear()
    get_tryon_provider.cache_clear()
    assert get_tryon_provider().name == "stub"


def test_routes_to_fashn_with_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TRYON_PROVIDER", "fashn")
    monkeypatch.setenv("FASHN_API_KEY", "k")
    get_settings.cache_clear()
    get_tryon_provider.cache_clear()
    assert get_tryon_provider().name == "fashn"
