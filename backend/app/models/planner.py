"""Mood Planner + Event Planner API models (spec §14, §15)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class MoodPlanRequest(BaseModel):
    """ "How do you want to feel today?" — and optionally, what for.

    Deliberately has NO render field. Escalating a plan into a paid render is a
    separate, explicit call to POST /v1/tryon (§14).
    """

    mood: str = Field(max_length=40)
    occasion: str | None = Field(default=None, max_length=40)


class MoodPlanResponse(BaseModel):
    id: str
    mood: str
    occasion: str | None = None
    headline: str
    lines: list[str] = Field(default_factory=list)
    #: Wardrobe item ids the direction referenced, in build order. Empty when
    #: the closet is too thin to name real pieces.
    item_ids: list[str] = Field(default_factory=list)
    #: True when no real pieces could be named — the app must not claim the
    #: direction was picked from the user's closet.
    generic: bool = False
    created_at: datetime


class StyleEventIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    event_at: datetime
    occasion: str | None = Field(default=None, max_length=40)
    #: The saved look this event is dressed for. Saved looks are device-local,
    #: so this is the look's stable id plus its durable image URL.
    look_ref: str | None = Field(default=None, max_length=120)
    look_image_url: str | None = Field(default=None, max_length=2000)
    note: str | None = Field(default=None, max_length=500)
    #: Opt-in per event. Default false: creating an event must never sign a user
    #: up for push (§23).
    reminder_opt_in: bool = False


class StyleEventUpdate(BaseModel):
    """Every field optional — a PATCH only changes what it names."""

    name: str | None = Field(default=None, min_length=1, max_length=120)
    event_at: datetime | None = None
    occasion: str | None = Field(default=None, max_length=40)
    look_ref: str | None = Field(default=None, max_length=120)
    look_image_url: str | None = Field(default=None, max_length=2000)
    note: str | None = Field(default=None, max_length=500)
    reminder_opt_in: bool | None = None


class StyleEvent(BaseModel):
    id: str
    name: str
    event_at: datetime
    occasion: str | None = None
    look_ref: str | None = None
    look_image_url: str | None = None
    note: str | None = None
    reminder_opt_in: bool = False
    created_at: datetime


class StyleEventList(BaseModel):
    events: list[StyleEvent] = Field(default_factory=list)
    #: The soonest upcoming event, repeated here so Home does not have to
    #: re-derive it from a list it may have paged.
    next_event: StyleEvent | None = None
