"""Schemas for the AI data-sharing consent API (privacy §10)."""

from __future__ import annotations

from pydantic import BaseModel, Field


class AiConsentResponse(BaseModel):
    """The user's current AI data-sharing consent, as the app should render it.

    `required_version` travels with the answer so the client never has to hold a
    hardcoded copy of the version the server is currently enforcing — that is the
    drift that would let a stale build believe an old grant is still good.
    """

    consent_type: str
    granted: bool
    version: int | None = None
    required_version: int
    provider_scope: str | None = None
    #: True only when granted AND at the required version. The single field the
    #: gate reads; everything else is for the settings screen and diagnostics.
    is_current: bool


class AiConsentGrantRequest(BaseModel):
    """An explicit grant. The version is echoed by the client so a build that
    displayed older copy cannot record agreement to newer terms it never showed.
    Clamped server-side to what we actually require."""

    consent_version: int = Field(ge=1)
