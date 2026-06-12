"""AI stylist — stub + Claude (injected client) + fallback + routing + gates."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.stylist import StylistSuggestRequest
from app.routers.v1.stylist import maybe_weather, suggest_with_fallback
from app.services.stylist import StylistContext, WardrobeBrief, get_stylist_provider
from app.services.stylist.anthropic_stylist import AnthropicStylist, _extract_json, build_prompt
from app.services.stylist.stub import StubStylist
from app.services.weather import WeatherSnapshot
from app.services.weather.stub import StubWeatherProvider

client = TestClient(app)


@pytest.fixture(autouse=True)
def _clear_cache():
    get_stylist_provider.cache_clear()
    get_settings.cache_clear()
    yield
    get_stylist_provider.cache_clear()
    get_settings.cache_clear()


def _wardrobe() -> list[WardrobeBrief]:
    return [
        WardrobeBrief(id="t1", title="Tee", category="Tops", color="white", tags=["casual"]),
        WardrobeBrief(id="b1", title="Jeans", category="Bottoms", color="blue"),
        WardrobeBrief(id="o1", title="Coat", category="Outerwear", color="black"),
    ]


def _ctx() -> StylistContext:
    return StylistContext()


async def _mild() -> WeatherSnapshot:
    return await StubWeatherProvider().current(latitude=0, longitude=0)


# ── stub stylist ─────────────────────────────────────────────────────────────


def test_stub_picks_top_and_bottom() -> None:
    sug = asyncio.run(StubStylist().suggest(wardrobe=_wardrobe(), weather=None, context=_ctx()))
    assert sug.item_ids == ["t1", "b1"]
    assert sug.title == "Everyday look"


def test_stub_adds_a_layer_when_cool() -> None:
    cold = WeatherSnapshot(condition="Overcast", temp_c=10.0, feels_like_c=8.0)
    sug = asyncio.run(StubStylist().suggest(wardrobe=_wardrobe(), weather=cold, context=_ctx()))
    assert sug.item_ids == ["t1", "b1", "o1"]
    assert "warm" in sug.rationale


def test_stub_empty_wardrobe_is_friendly() -> None:
    sug = asyncio.run(StubStylist().suggest(wardrobe=[], weather=None, context=_ctx()))
    assert sug.item_ids == []
    assert "empty" in sug.title.lower()


# ── Claude stylist (injected fake client, no SDK, no network) ────────────────


def _fake_anthropic(text: str) -> object:
    async def create(**kwargs):
        return SimpleNamespace(
            content=[SimpleNamespace(type="text", text=text)],
            usage=SimpleNamespace(input_tokens=42, output_tokens=18),
        )

    return SimpleNamespace(messages=SimpleNamespace(create=create))


def test_anthropic_parses_json_and_tokens() -> None:
    body = '{"item_ids": ["t1", "b1"], "title": "Smart casual", "rationale": "Mild day."}'
    stylist = AnthropicStylist("k", "claude-sonnet-4-6", client=_fake_anthropic(body))
    sug = asyncio.run(
        stylist.suggest(wardrobe=_wardrobe(), weather=asyncio.run(_mild()), context=_ctx())
    )
    assert sug.item_ids == ["t1", "b1"]
    assert sug.title == "Smart casual"
    assert sug.input_tokens == 42
    assert sug.output_tokens == 18


def test_anthropic_tolerates_prose_around_json() -> None:
    body = 'Sure! Here you go:\n{"item_ids": ["t1"], "title": "Look"}\nEnjoy.'
    stylist = AnthropicStylist("k", "m", client=_fake_anthropic(body))
    sug = asyncio.run(stylist.suggest(wardrobe=_wardrobe(), weather=None, context=_ctx()))
    assert sug.item_ids == ["t1"]


def test_extract_json_handles_garbage() -> None:
    assert _extract_json("no json here") == {}
    assert _extract_json('{"a": 1}') == {"a": 1}


def test_build_prompt_includes_items_and_weather() -> None:
    snap = asyncio.run(_mild())
    prompt = build_prompt(_wardrobe(), snap, StylistContext(occasion="work", note="warm pls"))
    assert "[t1]" in prompt and "Tops" in prompt
    assert "Partly cloudy" in prompt
    assert "Occasion: work" in prompt
    assert "Note: warm pls" in prompt


def test_brief_label_format() -> None:
    label = _wardrobe()[0].label()
    assert label.startswith("[t1]")
    assert "(Tops)" in label
    assert "casual" in label


def test_favorite_brief_label_shows_star() -> None:
    fav = WardrobeBrief(id="f1", title="Tee", category="Tops", favorite=True)
    plain = WardrobeBrief(id="p1", title="Tee", category="Tops")
    assert "★" in fav.label()
    assert "★" not in plain.label()


# ── graceful fallback ────────────────────────────────────────────────────────


class _BoomStylist:
    name = "boom"

    async def suggest(self, **kwargs):
        raise RuntimeError("provider down")


def test_fallback_to_stub_on_provider_failure() -> None:
    sug, ok = asyncio.run(
        suggest_with_fallback(_BoomStylist(), wardrobe=_wardrobe(), weather=None, context=_ctx())
    )
    assert ok is False
    assert sug.item_ids == ["t1", "b1"]  # the stub's deterministic pick


def test_fallback_passes_through_on_success() -> None:
    sug, ok = asyncio.run(
        suggest_with_fallback(StubStylist(), wardrobe=_wardrobe(), weather=None, context=_ctx())
    )
    assert ok is True
    assert sug.item_ids == ["t1", "b1"]


def test_maybe_weather_none_without_coords() -> None:
    assert asyncio.run(maybe_weather(None, None)) is None


# ── routing ──────────────────────────────────────────────────────────────────


def _route(
    monkeypatch: pytest.MonkeyPatch, *, anthropic: str, openai: str, primary: str = "anthropic"
):
    monkeypatch.setenv("ANTHROPIC_API_KEY", anthropic)
    monkeypatch.setenv("OPENAI_API_KEY", openai)
    monkeypatch.setenv("LLM_PRIMARY", primary)
    get_settings.cache_clear()
    get_stylist_provider.cache_clear()
    return get_stylist_provider()


def test_default_stylist_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    # Neither key set -> stub (ignore any real keys in a local .env).
    assert _route(monkeypatch, anthropic="", openai="").name == "stub"


def test_real_key_routes_to_anthropic(monkeypatch: pytest.MonkeyPatch) -> None:
    assert _route(monkeypatch, anthropic="sk-ant-realish-key", openai="").name == "anthropic"


def test_placeholder_key_stays_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    assert _route(monkeypatch, anthropic="sk-ant-xxxxxxxx", openai="").name == "stub"


def test_openai_only_routes_to_openai(monkeypatch: pytest.MonkeyPatch) -> None:
    assert _route(monkeypatch, anthropic="", openai="sk-realish-openai").name == "openai"


def test_both_keys_chain_anthropic_then_openai(monkeypatch: pytest.MonkeyPatch) -> None:
    # Both keys -> Claude leads, GPT is the automatic fallback (§2.1).
    assert _route(monkeypatch, anthropic="sk-ant-real", openai="sk-real").name == "anthropic+openai"


def test_llm_primary_openai_leads(monkeypatch: pytest.MonkeyPatch) -> None:
    p = _route(monkeypatch, anthropic="sk-ant-real", openai="sk-real", primary="openai")
    assert p.name == "openai+anthropic"


# ── request validation + auth gate ───────────────────────────────────────────


def test_request_rejects_out_of_range_coords() -> None:
    with pytest.raises(ValueError):
        StylistSuggestRequest(latitude=200, longitude=0)


def test_suggest_requires_token() -> None:
    resp = client.post("/v1/stylist/suggest", json={})
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "UNAUTHENTICATED"


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_stylist_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.wardrobe import _COLUMNS

    stmts = [
        f"select {_COLUMNS} from public.wardrobe_items "
        "where user_id = $1::uuid order by created_at desc limit 200",
        "insert into public.ai_usage_log "
        "(user_id, provider, task, input_tokens, output_tokens, images, "
        "estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, 'stylist', $3, $4, 0, $5, $6, $7)",
    ]

    async def run() -> None:
        import asyncpg

        conn = await asyncpg.connect(
            dsn=get_settings().connection_string, statement_cache_size=0, ssl="require"
        )
        try:
            for s in stmts:
                await conn.prepare(s)
        finally:
            await conn.close()

    asyncio.run(run())
