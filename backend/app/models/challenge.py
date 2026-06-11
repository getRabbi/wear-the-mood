from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class ChallengeResponse(BaseModel):
    """A style challenge (CLAUDE.md §1 pillar 4, §24)."""

    id: str
    slug: str
    title: str
    prompt: str | None = None
    cover_url: str | None = None
    starts_at: datetime
    ends_at: datetime | None = None
    entry_count: int = 0
    joined_by_me: bool = False


class ChallengeJoin(BaseModel):
    """Enter a challenge by linking one of your own OOTD posts to it."""

    post_id: UUID


class ChallengeEntryResponse(BaseModel):
    """A post entered into a challenge, with its author (for the entries feed)."""

    id: str
    challenge_id: str
    post_id: str
    user_id: str
    author_name: str | None = None
    image_url: str | None = None
    caption: str | None = None
    created_at: datetime = Field(...)
