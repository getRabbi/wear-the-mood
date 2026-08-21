"""Style Memory endpoints (spec §12, Phase 2/3).

View, feed, correct and reset what WTM has learned about a user's taste. Every
write path is gated on `feature_style_memory` server-side — the flag is not
merely a UI switch, so an old or hand-rolled client cannot write signals into a
feature that is supposed to be off.

Reads are deliberately NOT gated: a user must always be able to see and delete
what we hold about them, including after the feature is switched off (§10).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.flags import flag_enabled
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.style_memory import (
    PersonalizationToggle,
    StyleMemoryCorrection,
    StyleMemoryProfile,
    StyleMemoryResetResponse,
    StyleMemorySignalIn,
    StyleMemorySignalOut,
    StyleMemorySignalResponse,
)
from app.services import style_memory as sm

log = logging.getLogger("fashionos.style_memory")

router = APIRouter(tags=["style-memory"])


async def _require_enabled(conn: object) -> None:
    """Server-side gate for every WRITE. Reads stay open (§12.2)."""
    if not await flag_enabled(conn, sm.FLAG_STYLE_MEMORY, default=False):  # type: ignore[arg-type]
        raise ApiError(
            ErrorCode.NOT_FOUND,
            "Style Memory isn't available yet.",
            404,
        )


def _learned_line(before: dict, after: dict) -> str | None:
    """The restrained "WTM learned…" line (§12.4), or None.

    Only spoken when the summary ACTUALLY changed. Repeating the same sentence
    after every keep would turn a moment of delight into noise, and claiming to
    have learned something when nothing moved would simply be untrue.
    """
    summary = after.get("preference_summary")
    if not summary or summary == before.get("preference_summary"):
        return None
    return summary


@router.get("/style-memory", response_model=StyleMemoryProfile)
async def get_style_memory(
    user: CurrentUser = Depends(get_current_user),
) -> StyleMemoryProfile:
    """What WTM knows about this user's style. Always readable."""
    async with get_pool().acquire() as conn:
        return StyleMemoryProfile(**await sm.get_profile(conn, user.id))


@router.get("/style-memory/signals", response_model=list[StyleMemorySignalOut])
async def list_style_memory_signals(
    limit: int = 50,
    user: CurrentUser = Depends(get_current_user),
) -> list[StyleMemorySignalOut]:
    """The evidence behind the summary, newest first — the answer to "why does
    WTM think this?"."""
    limit = max(1, min(limit, 200))
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            "select id, signal_type, value, source, created_at "
            "from public.style_memory_signals where user_id = $1::uuid "
            "order by created_at desc limit $2",
            user.id,
            limit,
        )
    return [
        StyleMemorySignalOut(
            id=str(r["id"]),
            signal_type=r["signal_type"],
            value=r["value"],
            source=r["source"],
            created_at=r["created_at"],
        )
        for r in rows
    ]


@router.post("/style-memory/signals", response_model=StyleMemorySignalResponse)
async def add_style_memory_signal(
    body: StyleMemorySignalIn,
    user: CurrentUser = Depends(get_current_user),
) -> StyleMemorySignalResponse:
    """Record one taste signal.

    Descriptive attributes for a rendered look are resolved server-side from the
    user's own wardrobe rows (`look_attributes`) rather than trusted from the
    request: a client that could name its own colours could steer the profile
    into anything (§11).
    """
    async with get_pool().acquire() as conn:
        await _require_enabled(conn)
        before = await sm.get_profile(conn, user.id)

        context: dict = {}
        if body.reason:
            context["reason"] = body.reason
        if body.mood:
            context["mood"] = body.mood
        if body.occasion:
            context["occasion"] = body.occasion
        if body.entity_type == "tryon_job" and body.entity_id:
            context.update(await sm.look_attributes(conn, body.entity_id))

        try:
            recorded = await sm.record_signal(
                conn,
                user.id,
                signal_type=body.signal_type,
                entity_type=body.entity_type,
                entity_id=body.entity_id,
                value=body.value or body.mood or body.occasion,
                source="inferred",
                context=context,
                dedupe_key=body.dedupe_key,
            )
        except sm.StyleMemoryError as exc:
            raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc

        after = await sm.get_profile(conn, user.id)
    return StyleMemorySignalResponse(
        recorded=recorded,
        profile=StyleMemoryProfile(**after),
        learned=_learned_line(before, after) if recorded else None,
    )


@router.patch("/style-memory", response_model=StyleMemoryProfile)
async def correct_style_memory(
    body: StyleMemoryCorrection,
    user: CurrentUser = Depends(get_current_user),
) -> StyleMemoryProfile:
    """The user's own correction: state a preference, or remove one we inferred."""
    async with get_pool().acquire() as conn:
        await _require_enabled(conn)
        try:
            profile = await sm.apply_correction(
                conn, user.id, facet=body.facet, value=body.value, remove=body.remove
            )
        except sm.StyleMemoryError as exc:
            raise ApiError(ErrorCode.VALIDATION_ERROR, str(exc), 422) from exc
    return StyleMemoryProfile(**profile)


@router.post("/style-memory/personalization", response_model=StyleMemoryProfile)
async def set_personalization(
    body: PersonalizationToggle,
    user: CurrentUser = Depends(get_current_user),
) -> StyleMemoryProfile:
    """Stop (or resume) using Style Memory WITHOUT deleting it. Always allowed:
    turning personalization off must not require the feature to be on."""
    async with get_pool().acquire() as conn:
        profile = await sm.set_personalization(conn, user.id, enabled=body.enabled)
    return StyleMemoryProfile(**profile)


@router.post("/style-memory/reset", response_model=StyleMemoryResetResponse)
async def reset_style_memory(
    user: CurrentUser = Depends(get_current_user),
) -> StyleMemoryResetResponse:
    """Erase this user's Style Memory. Never gated — a deletion right does not
    depend on a feature flag (§10)."""
    async with get_pool().acquire() as conn:
        deleted = await sm.reset(conn, user.id)
        profile = await sm.get_profile(conn, user.id)
    log.info("style memory reset for user %s (%d signals)", user.id, deleted)
    return StyleMemoryResetResponse(deleted_signals=deleted, profile=StyleMemoryProfile(**profile))
