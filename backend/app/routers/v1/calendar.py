"""Calendar autopilot (CLAUDE.md §24) — an outfit for each upcoming event.

The app sends a batch of events (title/time/occasion only — no other calendar
data, §10); for each, the stylist suggests an outfit from the user's wardrobe,
reusing the daily-stylist machinery (weather + graceful fallback). One wardrobe
fetch per request; per-event calls are capped (the request model bounds the
batch) and logged to ai_usage_log task='calendar' (§14).
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.calendar import CalendarEventPlan, CalendarPlanRequest, CalendarPlanResponse
from app.models.stylist import StylistSuggestResponse
from app.routers.v1.stylist import maybe_weather, suggest_with_fallback
from app.routers.v1.wardrobe import _COLUMNS, _to_response
from app.services.stylist import StylistContext, WardrobeBrief, get_stylist_provider

log = logging.getLogger("fashionos.calendar")

router = APIRouter(tags=["calendar"])

_USD_PER_INPUT_TOK = Decimal("3") / Decimal("1000000")
_USD_PER_OUTPUT_TOK = Decimal("15") / Decimal("1000000")

_EMPTY = StylistSuggestResponse(
    title="Your closet is empty",
    rationale="Add a few pieces and I'll dress your calendar.",
    items=[],
)


@router.post("/calendar/plan", response_model=CalendarPlanResponse)
async def plan_calendar(
    body: CalendarPlanRequest,
    user: CurrentUser = Depends(get_current_user),
) -> CalendarPlanResponse:
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"select {_COLUMNS} from public.wardrobe_items "
            "where user_id = $1::uuid order by created_at desc limit 200",
            user.id,
        )

    if not rows:
        return CalendarPlanResponse(
            plans=[
                CalendarEventPlan(title=ev.title, starts_at=ev.starts_at, suggestion=_EMPTY)
                for ev in body.events
            ]
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
    by_id = {str(r["id"]): r for r in rows}
    weather = await maybe_weather(body.latitude, body.longitude)
    provider = get_stylist_provider()

    plans: list[CalendarEventPlan] = []
    usage: list[tuple] = []
    for ev in body.events:
        context = StylistContext(occasion=ev.occasion or ev.title)
        start = time.monotonic()
        suggestion, ok = await suggest_with_fallback(
            provider, wardrobe=briefs, weather=weather, context=context
        )
        latency = int((time.monotonic() - start) * 1000)

        picked = [by_id[i] for i in suggestion.item_ids if i in by_id]
        if not picked:
            picked = list(rows[:2])

        cost = Decimal("0")
        if suggestion.input_tokens is not None:
            cost = (
                Decimal(suggestion.input_tokens) * _USD_PER_INPUT_TOK
                + Decimal(suggestion.output_tokens or 0) * _USD_PER_OUTPUT_TOK
            )
        usage.append(
            (
                provider.name if ok else f"{provider.name}+stub",
                suggestion.input_tokens,
                suggestion.output_tokens,
                cost,
                latency,
                ok,
            )
        )
        plans.append(
            CalendarEventPlan(
                title=ev.title,
                starts_at=ev.starts_at,
                suggestion=StylistSuggestResponse(
                    title=suggestion.title,
                    rationale=suggestion.rationale,
                    items=[_to_response(r) for r in picked],
                ),
            )
        )

    async with get_pool().acquire() as conn:
        await conn.executemany(
            """
            insert into public.ai_usage_log
              (user_id, provider, task, input_tokens, output_tokens, images,
               estimated_usd, latency_ms, success)
            values ($1::uuid, $2, 'calendar', $3, $4, 0, $5, $6, $7)
            """,
            [(user.id, *u) for u in usage],
        )

    return CalendarPlanResponse(plans=plans)
