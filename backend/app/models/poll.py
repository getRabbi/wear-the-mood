"""Poll-under-post models (FEATURES_COMMUNITY_PLUS · Poll).

A poll is created with its post and rendered under it. Results are aggregate
counts only — the API never exposes who voted what beyond the caller's own
choice (§10).
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class PollCreate(BaseModel):
    """A poll attached to a new post: a question + 2–4 option labels."""

    question: str = Field(min_length=1, max_length=300)
    options: list[str]
    closes_at: datetime | None = None

    @field_validator("options")
    @classmethod
    def _clean_options(cls, value: list[str]) -> list[str]:
        cleaned: list[str] = []
        for raw in value:
            label = raw.strip()[:120]
            if label:
                cleaned.append(label)
        if not (2 <= len(cleaned) <= 4):
            raise ValueError("A poll needs 2–4 options.")
        return cleaned


class PollVote(BaseModel):
    option_index: int = Field(ge=0)


class PollOption(BaseModel):
    index: int
    label: str
    votes: int = 0


class PollResponse(BaseModel):
    id: str
    question: str
    options: list[PollOption]
    total_votes: int = 0
    my_choice: int | None = None  # the caller's chosen option index (only their own)
    closes_at: datetime | None = None
    is_closed: bool = False
