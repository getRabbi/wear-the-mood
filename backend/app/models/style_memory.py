"""Style Memory API models (spec §12).

Everything the user can SEE, CORRECT and RESET about what WTM has learned. The
shape is deliberately explicit rather than an opaque blob: each preference
carries its own confidence and whether the user stated it, because the UI has to
be able to tell "you told us this" apart from "we noticed this" (§12.3).
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.services.style_memory import FACETS, REJECTION_REASONS

RejectionReason = Literal[
    "identity_issue",
    "garment_issue",
    "not_my_style",
    "body_proportion_issue",
    "color_issue",
    "occasion_mismatch",
    "other",
]

Facet = Literal[
    "preferred_colors",
    "avoided_colors",
    "preferred_silhouettes",
    "avoided_silhouettes",
    "preferred_aesthetics",
    "preferred_occasions",
    "preferred_moods",
    "fit_visual_preferences",
]

# Guardrail: the Literal above and the service vocabulary must never drift.
assert set(FACETS) == set(Facet.__args__)  # type: ignore[attr-defined]
assert set(REJECTION_REASONS) == set(RejectionReason.__args__)  # type: ignore[attr-defined]


class PreferenceItem(BaseModel):
    value: str
    weight: float
    #: 0..1. Below ~0.35 the app must phrase this as a hunch, never a fact.
    confidence: float
    #: 'stated' = the user said so. 'inferred' = we noticed it.
    source: str
    updated_at: str


class StyleMemoryProfile(BaseModel):
    """The whole of what WTM believes about one user's taste."""

    version: int = 1
    confidence: float = 0
    signal_count: int = 0
    personalization_enabled: bool = True
    #: One hedged sentence, or null when we do not know enough to say anything.
    preference_summary: str | None = None
    preferred_colors: list[PreferenceItem] = Field(default_factory=list)
    avoided_colors: list[PreferenceItem] = Field(default_factory=list)
    preferred_silhouettes: list[PreferenceItem] = Field(default_factory=list)
    avoided_silhouettes: list[PreferenceItem] = Field(default_factory=list)
    preferred_aesthetics: list[PreferenceItem] = Field(default_factory=list)
    preferred_occasions: list[PreferenceItem] = Field(default_factory=list)
    preferred_moods: list[PreferenceItem] = Field(default_factory=list)
    fit_visual_preferences: list[PreferenceItem] = Field(default_factory=list)


class StyleMemorySignalIn(BaseModel):
    """A taste signal the app observed. `dedupe_key` makes a retry a no-op."""

    signal_type: Literal[
        "keep_look",
        "reject_look",
        "save_product",
        "unsave_product",
        "wear_again",
        "mood_selected",
        "occasion_selected",
        "share_look",
        "save_look",
        "manual_preference",
        "event_planned",
    ]
    entity_type: str | None = Field(default=None, max_length=40)
    entity_id: str | None = Field(default=None, max_length=120)
    value: str | None = Field(default=None, max_length=80)
    reason: RejectionReason | None = None
    #: Descriptive attributes the app already knows (mood, occasion). Colours and
    #: silhouettes for a rendered look are resolved SERVER-side from the user's
    #: own wardrobe rows, never accepted from the client.
    mood: str | None = Field(default=None, max_length=40)
    occasion: str | None = Field(default=None, max_length=40)
    dedupe_key: str | None = Field(default=None, max_length=120)


class StyleMemorySignalResponse(BaseModel):
    #: False when the dedupe key had already been recorded — an honest no-op.
    recorded: bool
    profile: StyleMemoryProfile
    #: The restrained "WTM learned…" line, or null when nothing new is sayable.
    learned: str | None = None


class StyleMemoryCorrection(BaseModel):
    facet: Facet
    value: str = Field(min_length=1, max_length=80)
    #: True removes this single entry instead of stating it.
    remove: bool = False


class PersonalizationToggle(BaseModel):
    enabled: bool


class StyleMemoryResetResponse(BaseModel):
    deleted_signals: int
    profile: StyleMemoryProfile


class TryOnFeedback(BaseModel):
    """The verdict on one render (§18).

    A rejection is a taste signal, NOT a refund request: technical and objective
    quality failures are already refunded by the worker before the user ever
    sees a result (§19.1/§19.2). This endpoint therefore never touches credits.
    """

    outcome: Literal["kept", "rejected"]
    reason: RejectionReason | None = None
    note: str | None = Field(default=None, max_length=280)


class TryOnFeedbackResponse(BaseModel):
    result_id: str
    outcome: str
    recorded: bool
    learned: str | None = None
    profile: StyleMemoryProfile | None = None


class StyleMemorySignalOut(BaseModel):
    """One raw signal, for the "why does WTM think this?" view."""

    id: str
    signal_type: str
    value: str | None = None
    source: str
    created_at: datetime
