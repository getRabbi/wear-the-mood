"""Packing planner — a stylist for a trip (CLAUDE.md §24).

Builds a packing list from the user's own wardrobe given trip length + occasion +
destination weather. Claude when a key is set (§2.1), else a deterministic
heuristic; on any LLM failure it degrades to the stub so the planner never
hard-fails. Logged to ai_usage_log task='packing' (§14). No credit / no job.
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.packing import PackingPlanRequest, PackingPlanResponse
from app.routers.v1.stylist import maybe_weather
from app.routers.v1.wardrobe import _COLUMNS, _to_response
from app.services.packing import (
    PackingContext,
    PackingList,
    PackingProvider,
    StubPacker,
    get_packing_provider,
)
from app.services.stylist import WardrobeBrief
from app.services.weather import WeatherSnapshot

log = logging.getLogger("fashionos.packing")

router = APIRouter(tags=["packing"])

# Claude Sonnet-class rates for cost visibility (§14); refine later.
_USD_PER_INPUT_TOK = Decimal("3") / Decimal("1000000")
_USD_PER_OUTPUT_TOK = Decimal("15") / Decimal("1000000")


def _ms(start: float) -> int:
    return int((time.monotonic() - start) * 1000)


def _cost(plan: PackingList) -> Decimal:
    if plan.input_tokens is None:
        return Decimal("0")
    return (
        Decimal(plan.input_tokens) * _USD_PER_INPUT_TOK
        + Decimal(plan.output_tokens or 0) * _USD_PER_OUTPUT_TOK
    )


async def plan_with_fallback(
    provider: PackingProvider,
    *,
    wardrobe: list[WardrobeBrief],
    weather: WeatherSnapshot | None,
    context: PackingContext,
) -> tuple[PackingList, bool]:
    """Run the primary planner; on any failure fall back to the stub heuristic so
    the user still gets a list (§2.1). Returns (plan, primary_succeeded)."""
    try:
        plan = await provider.plan(wardrobe=wardrobe, weather=weather, context=context)
        return plan, True
    except Exception as exc:  # resilience over a hard error
        log.warning("packing provider %s failed, using stub: %s", provider.name, exc)
        plan = await StubPacker().plan(wardrobe=wardrobe, weather=weather, context=context)
        return plan, False


@router.post("/packing/plan", response_model=PackingPlanResponse)
async def plan_packing(
    body: PackingPlanRequest,
    user: CurrentUser = Depends(get_current_user),
) -> PackingPlanResponse:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"select {_COLUMNS} from public.wardrobe_items "
            "where user_id = $1::uuid order by created_at desc limit 200",
            user.id,
        )

    if not rows:
        return PackingPlanResponse(
            title="Your closet is empty",
            notes="Add a few pieces and I'll pack for your trip.",
            items=[],
        )

    briefs = [
        WardrobeBrief(
            id=str(r["id"]),
            title=r["title"],
            category=r["category"],
            subcategory=r["subcategory"],
            color=r["color"],
            pattern=r["pattern"],
            tags=list(r["tags"] or []),
        )
        for r in rows
    ]
    weather = await maybe_weather(body.latitude, body.longitude)
    context = PackingContext(days=body.days, occasion=body.occasion, note=body.note)
    provider = get_packing_provider()

    start = time.monotonic()
    plan, ok = await plan_with_fallback(provider, wardrobe=briefs, weather=weather, context=context)
    latency = _ms(start)

    # Filter hallucinated ids; if nothing usable came back, fall back to the stub.
    by_id = {str(r["id"]): r for r in rows}
    picked = [by_id[i] for i in plan.item_ids if i in by_id]
    if not picked:
        plan = await StubPacker().plan(wardrobe=briefs, weather=weather, context=context)
        picked = [by_id[i] for i in plan.item_ids if i in by_id]

    async with get_pool().acquire() as conn:
        await conn.execute(
            """
            insert into public.ai_usage_log
              (user_id, provider, task, input_tokens, output_tokens, images,
               estimated_usd, latency_ms, success)
            values ($1::uuid, $2, 'packing', $3, $4, 0, $5, $6, $7)
            """,
            user.id,
            provider.name if ok else f"{provider.name}+stub",
            plan.input_tokens,
            plan.output_tokens,
            _cost(plan),
            latency,
            ok,
        )

    return PackingPlanResponse(
        title=plan.title,
        notes=plan.notes,
        items=[_to_response(r) for r in picked],
    )
