from __future__ import annotations

from pydantic import BaseModel, Field


class FlagsResponse(BaseModel):
    """Enabled-state of every feature flag (CLAUDE.md §16). The client treats a
    flag absent from this map as OFF, so a new feature stays dark until it's
    explicitly enabled in the `feature_flags` table."""

    flags: dict[str, bool] = Field(default_factory=dict)
