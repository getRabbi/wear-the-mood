"""Mood Planner v2 + Event Planner endpoints (spec §14, §15, Phase 4).

Both are the cheap half of the product: a reason to open WTM that costs nothing
to serve and nothing to use. Neither endpoint reserves a credit, calls a
provider, or can cause a render — escalating a plan into an image is a separate,
explicit POST /v1/tryon that the user asks for by name.

Each surface is gated on its own flag, server-side, so an old client cannot
write into a feature that is switched off.
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Response

from app.core.db import get_pool
from app.core.errors import ApiError
from app.core.flags import flag_enabled
from app.core.supabase_auth import CurrentUser, get_current_user
from app.models.common import ErrorCode
from app.models.planner import (
    MoodPlanRequest,
    MoodPlanResponse,
    StyleEvent,
    StyleEventIn,
    StyleEventList,
    StyleEventUpdate,
)
from app.services import style_memory as sm
from app.services.planner import MOODS, build_direction

log = logging.getLogger("fashionos.planner")

router = APIRouter(tags=["planner"])

FLAG_MOOD_PLANNER = "feature_mood_planner_v2"
FLAG_EVENT_PLANNER = "feature_event_planner"

#: Wardrobe columns the direction builder reads. A narrow projection on purpose:
#: a planner that selected * would pull cutout URLs and embeddings it never uses.
_WARDROBE_COLS = "id, title, category, subcategory, color, canonical_category"

#: How many pieces the direction considers. Enough to find one per layer in a
#: real closet, bounded so a 2,000-item wardrobe cannot make Home slow (§50).
_WARDROBE_LIMIT = 120


async def _require(conn: object, flag: str, what: str) -> None:
    if not await flag_enabled(conn, flag, default=False):  # type: ignore[arg-type]
        raise ApiError(ErrorCode.NOT_FOUND, f"{what} isn't available yet.", 404)


def _event(row: object) -> StyleEvent:
    return StyleEvent(
        id=str(row["id"]),  # type: ignore[index]
        name=row["name"],  # type: ignore[index]
        event_at=row["event_at"],  # type: ignore[index]
        occasion=row["occasion"],  # type: ignore[index]
        look_ref=row["look_ref"],  # type: ignore[index]
        look_image_url=row["look_image_url"],  # type: ignore[index]
        note=row["note"],  # type: ignore[index]
        reminder_opt_in=row["reminder_opt_in"],  # type: ignore[index]
        created_at=row["created_at"],  # type: ignore[index]
    )


#: Columns that are NOT NULL on `style_events`, so a PATCH may never null them.
_REQUIRED_FIELDS = ("name", "event_at", "reminder_opt_in")

_EVENT_COLS = (
    "id, name, event_at, occasion, look_ref, look_image_url, note, reminder_opt_in, created_at"
)


# ── Mood Planner ─────────────────────────────────────────────────────────────


@router.post("/plans/mood", response_model=MoodPlanResponse)
async def create_mood_plan(
    body: MoodPlanRequest,
    user: CurrentUser = Depends(get_current_user),
) -> MoodPlanResponse:
    """Turn a mood (and optional context) into styling direction.

    Costs nothing and renders nothing. The mood and occasion are also recorded
    as Style Memory signals when that feature is on — a repeated Tuesday-morning
    "work / calm" is one of the most honest taste signals the product has.
    """
    mood = body.mood.strip().lower()
    if mood not in MOODS:
        raise ApiError(
            ErrorCode.VALIDATION_ERROR, f"Unknown mood. Expected one of: {', '.join(MOODS)}.", 422
        )
    occasion = (body.occasion or "").strip().lower() or None

    async with get_pool().acquire() as conn:
        await _require(conn, FLAG_MOOD_PLANNER, "The mood planner")

        wardrobe = await conn.fetch(
            f"select {_WARDROBE_COLS} from public.wardrobe_items "
            "where user_id = $1::uuid order by created_at desc limit $2",
            user.id,
            _WARDROBE_LIMIT,
        )
        # Style Memory only REORDERS candidates, and only when the user has not
        # turned personalization off. A user with neither still gets a full plan.
        preferred: list[str] = []
        profile = await sm.get_profile(conn, user.id)
        if profile.get("personalization_enabled", True):
            preferred = [e["value"] for e in profile.get("preferred_colors", [])]

        direction = build_direction(
            mood=mood, occasion=occasion, wardrobe=list(wardrobe), preferred_colors=preferred
        )
        row = await conn.fetchrow(
            """
            insert into public.mood_plans (user_id, mood, occasion, direction)
            values ($1::uuid, $2, $3, $4::jsonb)
            returning id, created_at
            """,
            user.id,
            mood,
            occasion,
            json.dumps(direction.as_json()),
        )

        # Best-effort: the plan is the product, the signal is bookkeeping.
        if await flag_enabled(conn, sm.FLAG_STYLE_MEMORY, default=False):
            try:
                await sm.record_signal(
                    conn,
                    user.id,
                    signal_type="mood_selected",
                    value=mood,
                    entity_type="mood_plan",
                    entity_id=str(row["id"]),
                )
                if occasion:
                    await sm.record_signal(
                        conn,
                        user.id,
                        signal_type="occasion_selected",
                        value=occasion,
                        entity_type="mood_plan",
                        entity_id=str(row["id"]),
                    )
            except Exception as exc:  # pragma: no cover - defensive
                log.warning("mood plan signal not recorded: %s", exc)

    return MoodPlanResponse(
        id=str(row["id"]),
        created_at=row["created_at"],
        **direction.as_json(),
    )


@router.get("/plans/mood/latest", response_model=MoodPlanResponse | None)
async def latest_mood_plan(
    user: CurrentUser = Depends(get_current_user),
) -> MoodPlanResponse | None:
    """The user's most recent plan, so "Continue your style" shows the SAME
    direction rather than silently re-rolling it. Null when there is none."""
    async with get_pool().acquire() as conn:
        row = await conn.fetchrow(
            "select id, mood, occasion, direction, created_at from public.mood_plans "
            "where user_id = $1::uuid order by created_at desc limit 1",
            user.id,
        )
    if row is None:
        return None
    raw = row["direction"]
    data = json.loads(raw) if isinstance(raw, str) else (raw or {})
    return MoodPlanResponse(
        id=str(row["id"]),
        mood=row["mood"],
        occasion=row["occasion"],
        headline=data.get("headline", ""),
        lines=list(data.get("lines") or []),
        item_ids=list(data.get("item_ids") or []),
        generic=bool(data.get("generic", False)),
        created_at=row["created_at"],
    )


# ── Event Planner ────────────────────────────────────────────────────────────


@router.get("/events", response_model=StyleEventList)
async def list_events(
    include_past: bool = False,
    user: CurrentUser = Depends(get_current_user),
) -> StyleEventList:
    """The user's saved events, soonest first.

    Readable even when the feature flag is off: a user must always be able to
    see (and delete) what they saved, including after a kill-switch (§51).
    """
    async with get_pool().acquire() as conn:
        rows = await conn.fetch(
            f"select {_EVENT_COLS} from public.style_events "
            "where user_id = $1::uuid and ($2 or event_at >= now() - interval '1 day') "
            "order by event_at asc limit 100",
            user.id,
            include_past,
        )
    events = [_event(r) for r in rows]
    # The soonest event that has NOT happened yet. The rows are already sorted
    # ascending, but `include_past` can put yesterday's dinner at the front, and
    # Home offering to dress the user for it would be worse than showing
    # nothing.
    now = datetime.now(UTC)
    upcoming = next((e for e in events if e.event_at > now), None)
    return StyleEventList(events=events, next_event=upcoming)


@router.post("/events", response_model=StyleEvent, status_code=201)
async def create_event(
    body: StyleEventIn,
    user: CurrentUser = Depends(get_current_user),
) -> StyleEvent:
    """Save an event. No calendar permission is requested and no calendar is
    read or written — this is what the user typed (§15)."""
    async with get_pool().acquire() as conn:
        await _require(conn, FLAG_EVENT_PLANNER, "The event planner")
        row = await conn.fetchrow(
            f"""
            insert into public.style_events
              (user_id, name, event_at, occasion, look_ref, look_image_url,
               note, reminder_opt_in)
            values ($1::uuid, $2, $3, $4, $5, $6, $7, $8)
            returning {_EVENT_COLS}
            """,
            user.id,
            body.name.strip(),
            body.event_at,
            body.occasion,
            body.look_ref,
            body.look_image_url,
            body.note,
            body.reminder_opt_in,
        )
        if body.occasion and await flag_enabled(conn, sm.FLAG_STYLE_MEMORY, default=False):
            try:
                await sm.record_signal(
                    conn,
                    user.id,
                    signal_type="event_planned",
                    value=body.occasion,
                    entity_type="style_event",
                    entity_id=str(row["id"]),
                )
            except Exception as exc:  # pragma: no cover - defensive
                log.warning("event signal not recorded: %s", exc)
    return _event(row)


@router.patch("/events/{event_id}", response_model=StyleEvent)
async def update_event(
    event_id: UUID,
    body: StyleEventUpdate,
    user: CurrentUser = Depends(get_current_user),
) -> StyleEvent:
    """Change what the user named. Scoped by user_id in the UPDATE itself, so
    somebody else's event is a 404 rather than a late authorization check."""
    fields = body.model_dump(exclude_unset=True)
    # `exclude_unset` distinguishes "not mentioned" from "explicitly null", and
    # the three NOT NULL columns can only take the first. A client sending
    # `{"name": null}` means "clear it", which this table cannot express — so it
    # is a typed 422 rather than a NotNullViolation surfacing as a 500 (§13).
    for required in _REQUIRED_FIELDS:
        if required in fields and fields[required] is None:
            raise ApiError(ErrorCode.VALIDATION_ERROR, f"{required} can't be empty.", 422)
    if not fields:
        raise ApiError(ErrorCode.VALIDATION_ERROR, "Nothing to update.", 422)
    if "name" in fields:
        fields["name"] = str(fields["name"]).strip()
        if not fields["name"]:
            raise ApiError(ErrorCode.VALIDATION_ERROR, "name can't be empty.", 422)

    assignments = ", ".join(f"{key} = ${i + 3}" for i, key in enumerate(fields))
    async with get_pool().acquire() as conn:
        await _require(conn, FLAG_EVENT_PLANNER, "The event planner")
        row = await conn.fetchrow(
            f"""
            update public.style_events set {assignments}
             where id = $1::uuid and user_id = $2::uuid
            returning {_EVENT_COLS}
            """,
            str(event_id),
            user.id,
            *fields.values(),
        )
        if row is None:
            raise ApiError(ErrorCode.NOT_FOUND, "Event not found.", 404)
    return _event(row)


@router.delete("/events/{event_id}", status_code=204)
async def delete_event(
    event_id: UUID,
    user: CurrentUser = Depends(get_current_user),
) -> Response:
    """Remove an event. Never flag-gated: deleting your own data must work even
    after the feature it belongs to has been switched off."""
    async with get_pool().acquire() as conn:
        deleted = await conn.fetchval(
            "delete from public.style_events where id = $1::uuid and user_id = $2::uuid "
            "returning id",
            str(event_id),
            user.id,
        )
    if deleted is None:
        raise ApiError(ErrorCode.NOT_FOUND, "Event not found.", 404)
    return Response(status_code=204)
