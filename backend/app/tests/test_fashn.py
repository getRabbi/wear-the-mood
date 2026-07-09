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


def test_429_raises_capacity_error() -> None:
    # A 429 (rate limit / FASHN account out of credits — the mobile-QA root
    # cause) is classified as CAPACITY: still transient/retryable, but the
    # worker stores its own honest "studio unavailable" message on exhaust.
    from app.services.tryon.base import TryOnCapacityError, TryOnTransientError

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": "Out of API credits"})

    with pytest.raises(TryOnCapacityError) as exc:
        asyncio.run(_provider(handler).generate(person_image_url="p", garment_image_url="g"))
    assert isinstance(exc.value, TryOnTransientError)  # retry behaviour intact
    assert "429" in str(exc.value)


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
        return httpx.Response(200, json={"id": "job-x", "status": "completed", "output": output})

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
            product_image="data:image/png;base64,QQ==", prompt="studio"
        )
    )
    assert out == "https://cdn/m.png"
    assert posted["model_name"] == "product-to-model"
    assert posted["inputs"]["product_image"] == "data:image/png;base64,QQ=="


def test_model_create_returns_all_candidates() -> None:
    # Mannequin candidates → FASHN Model Create (spend cap → ONE per call).
    posted: dict = {}
    out = asyncio.run(
        _provider(_capturing(["u1"], posted)).model_create(prompt="mannequin", num_images=3)
    )
    assert out == ["u1"]
    assert posted["model_name"] == "model-create"
    assert posted["inputs"]["num_images"] == 1  # clamped by the spend cap


# ── FASHN spend cap: no request may exceed 1 external credit per result ───────


def _posted_for(coro_factory) -> dict:
    posted: dict = {}
    asyncio.run(coro_factory(_provider(_capturing(["https://cdn/x.png"], posted))))
    return posted


def test_every_fashn_builder_stays_within_one_credit() -> None:
    """Every request builder — try-on (Couture/Full Look/HD share it), Enhance
    (Edit), catalog (Product-to-Model), mannequin (Model Create) — posts a body
    the published pricing table prices at exactly ≤1 credit per result."""
    from app.services.tryon.fashn import (
        MAX_FASHN_CREDITS_PER_RESULT,
        fashn_estimated_credits,
    )

    builders = {
        "tryon": lambda p: p.generate(person_image_url="p", garment_image_url="g"),
        "edit": lambda p: p.edit_image(image="i", prompt="clean"),
        "product-to-model": lambda p: p.product_to_model(product_image="i", prompt="s"),
        "model-create": lambda p: p.model_create(prompt="m", num_images=4),
    }
    for name, factory in builders.items():
        posted = _posted_for(factory)
        cost = fashn_estimated_credits(posted["model_name"], posted["inputs"])
        assert cost <= MAX_FASHN_CREDITS_PER_RESULT, f"{name} would cost {cost}"
        # Generation models must be pinned to the only ≤1-credit configuration.
        if not posted["model_name"].startswith("tryon-v"):
            assert posted["inputs"]["generation_mode"] == "fast"
            assert posted["inputs"]["resolution"] == "1k"
            assert posted["inputs"].get("num_images", 1) == 1


def test_spend_cap_clamps_hostile_inputs() -> None:
    """Even a caller that asks for quality·4k·4-images gets clamped to fast·1k·1
    before the request leaves the provider (retries re-enter the same funnel)."""
    posted: dict = {}
    provider = _provider(_capturing(["u"], posted))
    asyncio.run(
        provider._run_outputs(  # the single choke point every call flows through
            "edit",
            {
                "image": "i",
                "prompt": "p",
                "generation_mode": "quality",
                "resolution": "4k",
                "num_images": 4,
                "face_reference": "f",
            },
        )
    )
    assert posted["inputs"]["generation_mode"] == "fast"
    assert posted["inputs"]["resolution"] == "1k"
    assert posted["inputs"]["num_images"] == 1
    assert "face_reference" not in posted["inputs"]


def test_estimator_matches_published_pricing_table() -> None:
    from app.services.tryon.fashn import fashn_estimated_credits

    # Fixed-rate: try-on is 1 credit at any mode.
    assert fashn_estimated_credits("tryon-v1.6", {"mode": "quality"}) == 1
    # Generation models: fast/balanced/quality = 1/2/3 at 1k, +1 per step up.
    assert fashn_estimated_credits("edit", {"generation_mode": "fast"}) == 1
    assert fashn_estimated_credits("edit", {"generation_mode": "quality"}) == 3
    assert (
        fashn_estimated_credits(
            "product-to-model", {"generation_mode": "quality", "resolution": "2k"}
        )
        == 4
    )
    # Omitted mode bills as fast@1k / balanced@2k ("automatic pricing").
    assert fashn_estimated_credits("edit", {}) == 1
    assert fashn_estimated_credits("edit", {"resolution": "2k"}) == 3
    # Unknown settings price pessimistically — they can never pass the cap.
    assert fashn_estimated_credits("edit", {"generation_mode": "ultra"}) > 1


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
