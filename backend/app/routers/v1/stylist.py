"""AI stylist — "what do I wear today?" (CLAUDE.md §1, §2.1, pillar 3).

Synchronous: picks an outfit from the user's own wardrobe with Claude Sonnet
(primary, §2.1) plus today's weather (§2). It's a cheap text call, so no async
job — but every call is logged to ai_usage_log (§14). On an LLM failure it
degrades gracefully to the deterministic stub so the daily habit never hard-fails.
"""

from __future__ import annotations

import logging
import time
from decimal import Decimal

import asyncpg
from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.stylist import StylistSuggestRequest, StylistSuggestResponse
from app.routers.v1.wardrobe import _COLUMNS, _to_response
from app.services.stylist import (
    StylistContext,
    StylistProvider,
    StylistSuggestion,
    WardrobeBrief,
    get_stylist_provider,
)
from app.services.stylist.stub import StubStylist
from app.services.taste import taste_centroid
from app.services.weather import WeatherSnapshot, get_weather_provider

log = logging.getLogger("fashionos.stylist")

router = APIRouter(tags=["stylist"])

# How many of the closest-to-taste items to flag as favorites for the stylist.
_FAVORITE_COUNT = 5

# Rough Claude Sonnet-class rates for cost visibility (§14); refine later.
_USD_PER_INPUT_TOK = Decimal("3") / Decimal("1000000")
_USD_PER_OUTPUT_TOK = Decimal("15") / Decimal("1000000")


async def _favorite_ids(conn: asyncpg.Connection, user_id: str) -> set[str]:
    """Ids of the wardrobe items nearest the user's taste centroid (§24). Empty
    when there are no embedded taste signals yet (no OpenAI key / worker, or the
    user hasn't interacted), so the stylist falls back to no taste bias."""
    centroid = await taste_centroid(conn, user_id)
    if centroid is None:
        return set()
    rows = await conn.fetch(
        """
        select id::text as id
          from public.wardrobe_items
         where user_id = $1::uuid and embedding is not null
         order by embedding <=> $2::vector
         limit $3
        """,
        user_id,
        centroid,
        _FAVORITE_COUNT,
    )
    return {r["id"] for r in rows}


async def _fetch_wardrobe(
    conn: asyncpg.Connection, user_id: str
) -> tuple[list[asyncpg.Record], set[str]]:
    """Load the user's wardrobe plus the ids closest to their taste vector (§24)
    so the stylist can prefer pieces they actually like."""
    rows = await conn.fetch(
        f"""
        select {_COLUMNS}
          from public.wardrobe_items
         where user_id = $1::uuid
         order by created_at desc
         limit 200
        """,
        user_id,
    )
    favorites = await _favorite_ids(conn, user_id)
    return rows, favorites


def _ms(start: float) -> int:
    return int((time.monotonic() - start) * 1000)


def _cost(s: StylistSuggestion) -> Decimal:
    if s.input_tokens is None:
        return Decimal("0")
    return (
        Decimal(s.input_tokens) * _USD_PER_INPUT_TOK
        + Decimal(s.output_tokens or 0) * _USD_PER_OUTPUT_TOK
    )


async def maybe_weather(latitude: float | None, longitude: float | None) -> WeatherSnapshot | None:
    """Weather is enriching context, never a hard dependency (§2) — swallow any
    failure and let the stylist proceed without it."""
    if latitude is None or longitude is None:
        return None
    try:
        return await get_weather_provider().current(latitude=latitude, longitude=longitude)
    except Exception as exc:  # degrade gracefully
        log.warning("weather lookup failed: %s", exc)
        return None


async def suggest_with_fallback(
    provider: StylistProvider,
    *,
    wardrobe: list[WardrobeBrief],
    weather: WeatherSnapshot | None,
    context: StylistContext,
) -> tuple[StylistSuggestion, bool]:
    """Run the primary stylist; on any failure fall back to the stub so the user
    still gets an outfit (§2.1). Returns (suggestion, primary_succeeded)."""
    try:
        suggestion = await provider.suggest(wardrobe=wardrobe, weather=weather, context=context)
        return suggestion, True
    except Exception as exc:  # resilience over a hard error
        log.warning("stylist provider %s failed, using stub: %s", provider.name, exc)
        suggestion = await StubStylist().suggest(
            wardrobe=wardrobe, weather=weather, context=context
        )
        return suggestion, False


async def _log_usage(
    conn: asyncpg.Connection,
    *,
    user_id: str,
    provider: str,
    suggestion: StylistSuggestion,
    success: bool,
    latency_ms: int,
) -> None:
    await conn.execute(
        """
        insert into public.ai_usage_log
          (user_id, provider, task, input_tokens, output_tokens, images,
           estimated_usd, latency_ms, success)
        values ($1::uuid, $2, 'stylist', $3, $4, 0, $5, $6, $7)
        """,
        user_id,
        provider,
        suggestion.input_tokens,
        suggestion.output_tokens,
        _cost(suggestion),
        latency_ms,
        success,
    )


@router.post("/stylist/suggest", response_model=StylistSuggestResponse)
async def suggest_outfit(
    body: StylistSuggestRequest,
    user: CurrentUser = Depends(get_current_user),
) -> StylistSuggestResponse:
    async with get_pool().acquire() as conn:
        rows, favorites = await _fetch_wardrobe(conn, user.id)

    if not rows:
        return StylistSuggestResponse(
            title="Your closet is empty",
            rationale="Add a few pieces and I'll put an outfit together for you.",
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
            favorite=str(r["id"]) in favorites,
        )
        for r in rows
    ]
    weather = await maybe_weather(body.latitude, body.longitude)
    context = StylistContext(occasion=body.occasion, note=body.note)
    provider = get_stylist_provider()

    start = time.monotonic()
    suggestion, ok = await suggest_with_fallback(
        provider, wardrobe=briefs, weather=weather, context=context
    )
    latency = _ms(start)

    # Defend against hallucinated ids: keep only items that are really the user's.
    by_id = {str(r["id"]): r for r in rows}
    picked = [by_id[i] for i in suggestion.item_ids if i in by_id]
    if not picked:  # nothing usable came back — still show a couple of pieces
        picked = list(rows[:2])

    async with get_pool().acquire() as conn:
        await _log_usage(
            conn,
            user_id=user.id,
            provider=provider.name if ok else f"{provider.name}+stub",
            suggestion=suggestion,
            success=ok,
            latency_ms=latency,
        )

    return StylistSuggestResponse(
        title=suggestion.title,
        rationale=suggestion.rationale,
        items=[_to_response(r) for r in picked],
    )
