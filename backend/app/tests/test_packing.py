"""Packing planner (CLAUDE.md §24) — heuristic counts, stub picks, fallback,
routing, validation, live SQL."""

from __future__ import annotations

import asyncio

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.models.packing import PackingPlanRequest
from app.routers.v1.packing import plan_with_fallback
from app.services.packing import PackingContext, StubPacker, get_packing_provider, plan_counts
from app.services.stylist import WardrobeBrief
from app.services.weather import WeatherSnapshot

client = TestClient(app)


@pytest.fixture(autouse=True)
def _clear_cache():
    get_packing_provider.cache_clear()
    get_settings.cache_clear()
    yield
    get_packing_provider.cache_clear()
    get_settings.cache_clear()


def _wardrobe() -> list[WardrobeBrief]:
    return [
        WardrobeBrief(id="t1", title="Tee", category="Tops"),
        WardrobeBrief(id="t2", title="Shirt", category="Tops"),
        WardrobeBrief(id="t3", title="Polo", category="Tops"),
        WardrobeBrief(id="b1", title="Jeans", category="Bottoms"),
        WardrobeBrief(id="b2", title="Chinos", category="Bottoms"),
        WardrobeBrief(id="o1", title="Coat", category="Outerwear"),
        WardrobeBrief(id="s1", title="Sneakers", category="Shoes"),
        WardrobeBrief(id="s2", title="Boots", category="Shoes"),
    ]


# ── heuristic counts ─────────────────────────────────────────────────────────


def test_plan_counts_scale_with_days() -> None:
    c = plan_counts(4, want_outerwear=True)
    assert c["tops"] == 3  # ceil(4 * 0.7)
    assert c["bottoms"] == 2  # ceil(4 / 2)
    assert c["outerwear"] == 1
    assert c["shoes"] == 2


def test_plan_counts_no_outerwear_when_warm() -> None:
    assert plan_counts(3, want_outerwear=False)["outerwear"] == 0


# ── stub packer ──────────────────────────────────────────────────────────────


def _cold() -> WeatherSnapshot:
    return WeatherSnapshot(condition="Overcast", temp_c=8.0, feels_like_c=6.0)


def test_stub_packs_by_category_and_days() -> None:
    plan = asyncio.run(
        StubPacker().plan(
            wardrobe=_wardrobe(), weather=_cold(), context=PackingContext(days=4)
        )
    )
    # 3 tops + 2 bottoms + 1 outerwear (cold) + 2 shoes = 8
    assert plan.item_ids == ["t1", "t2", "t3", "b1", "b2", "o1", "s1", "s2"]
    assert "4 days" in plan.title


def test_stub_warm_skips_outerwear() -> None:
    warm = WeatherSnapshot(condition="Clear", temp_c=28.0, feels_like_c=30.0)
    plan = asyncio.run(
        StubPacker().plan(
            wardrobe=_wardrobe(), weather=warm, context=PackingContext(days=2)
        )
    )
    assert "o1" not in plan.item_ids  # no layer when warm


def test_stub_packs_a_layer_when_weather_unknown() -> None:
    plan = asyncio.run(
        StubPacker().plan(wardrobe=_wardrobe(), weather=None, context=PackingContext(days=3))
    )
    assert "o1" in plan.item_ids  # play it safe without weather


# ── fallback + routing ───────────────────────────────────────────────────────


class _BoomPacker:
    name = "boom"

    async def plan(self, **kwargs):
        raise RuntimeError("provider down")


def test_fallback_to_stub_on_failure() -> None:
    plan, ok = asyncio.run(
        plan_with_fallback(
            _BoomPacker(), wardrobe=_wardrobe(), weather=None, context=PackingContext(days=2)
        )
    )
    assert ok is False and plan.item_ids  # the stub still produced a list


def test_default_packer_is_stub(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "")
    get_settings.cache_clear()
    get_packing_provider.cache_clear()
    assert get_packing_provider().name == "stub"


def test_real_key_routes_to_anthropic(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-realish-key")
    get_settings.cache_clear()
    get_packing_provider.cache_clear()
    assert get_packing_provider().name == "anthropic"


# ── validation + auth ────────────────────────────────────────────────────────


def test_request_requires_days() -> None:
    with pytest.raises(ValueError):
        PackingPlanRequest()  # days is required


def test_request_rejects_out_of_range_days() -> None:
    with pytest.raises(ValueError):
        PackingPlanRequest(days=0)


def test_plan_requires_token() -> None:
    resp = client.post("/v1/packing/plan", json={"days": 3})
    assert resp.status_code == 401


# ── live schema validation (skips without a DSN) ─────────────────────────────


def test_packing_sql_valid_live() -> None:
    if not get_settings().connection_string:
        pytest.skip("CONNECTION_STRING not set; skipping live DB check")

    from app.routers.v1.wardrobe import _COLUMNS

    stmts = [
        f"select {_COLUMNS} from public.wardrobe_items "
        "where user_id = $1::uuid order by created_at desc limit 200",
        "insert into public.ai_usage_log "
        "(user_id, provider, task, input_tokens, output_tokens, images, "
        "estimated_usd, latency_ms, success) "
        "values ($1::uuid, $2, 'packing', $3, $4, 0, $5, $6, $7)",
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
