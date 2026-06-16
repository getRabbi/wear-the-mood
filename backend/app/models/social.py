from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator


class PostCreate(BaseModel):
    """Create an OOTD post (CLAUDE.md §1 pillar 4). A post needs visible content
    — an image (any photo, a try-on result, or an outfit cover) and/or one of the
    user's own outfits — plus optional tags."""

    caption: str | None = Field(default=None, max_length=2000)
    image_url: str | None = Field(default=None, max_length=2000)
    outfit_id: UUID | None = None
    tags: list[str] = Field(default_factory=list)

    @field_validator("tags")
    @classmethod
    def _clean_tags(cls, value: list[str]) -> list[str]:
        cleaned: list[str] = []
        for raw in value:
            tag = raw.strip().lstrip("#")[:30]
            if tag and tag not in cleaned:
                cleaned.append(tag)
        return cleaned[:10]  # cap at 10 tags

    @model_validator(mode="after")
    def _require_content(self) -> PostCreate:
        if not self.image_url and self.outfit_id is None:
            raise ValueError("A post needs an image or an outfit.")
        return self


class PostResponse(BaseModel):
    id: str
    user_id: str
    author_name: str | None = None
    caption: str | None = None
    image_url: str | None = None
    outfit_id: str | None = None
    tags: list[str] = Field(default_factory=list)
    like_count: int = 0
    comment_count: int = 0
    liked_by_me: bool = False
    created_at: datetime


class CommentCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)


class CommentResponse(BaseModel):
    id: str
    post_id: str
    user_id: str
    author_name: str | None = None
    body: str
    created_at: datetime


class ReportCreate(BaseModel):
    """File a UGC report (CLAUDE.md §19). The subject is a post, comment, or user."""

    subject_type: Literal["post", "comment", "user"]
    subject_id: UUID
    reason: str | None = Field(default=None, max_length=500)


# ── public creator profiles + follow graph (CLAUDE.md §1 pillar 4) ───────────


class PublicUserCard(BaseModel):
    """A creator in a followers / following list. Only ever the safe public
    fields — never the sensitive columns that also live on `profiles` (§10)."""

    user_id: str
    display_name: str | None = None
    username: str | None = None
    style_tags: list[str] = Field(default_factory=list)
    is_following: bool = False  # whether the *caller* follows this user
    is_me: bool = False


class PublicClosetItem(BaseModel):
    """A shared wardrobe item on a creator's public closet (CLAUDE.md §1 pillar 4).
    SAFE fields only — image + name + category + colour. Never cost, brand,
    wear data, or anything private (§10)."""

    id: str
    title: str | None = None
    category: str | None = None
    color: str | None = None
    image_url: str | None = None
    cutout_url: str | None = None
    thumbnail_url: str | None = None


class PublicProfileResponse(BaseModel):
    """A creator's PUBLIC profile (CLAUDE.md §1 pillar 4). Safe fields only —
    no email, phone, body data, or private photo paths (§10)."""

    user_id: str
    display_name: str | None = None
    username: str | None = None
    bio: str | None = None
    style_tags: list[str] = Field(default_factory=list)
    follower_count: int = 0
    following_count: int = 0
    post_count: int = 0
    is_following: bool = False  # whether the caller follows this user
    is_me: bool = False


# ── Style-Score leaderboard (CLAUDE.md §1 pillar 4, §24) ─────────────────────


class LeaderboardEntry(BaseModel):
    rank: int
    user_id: str
    display_name: str | None = None
    score: int
    is_me: bool = False


class PastWinner(BaseModel):
    month: str  # "YYYY-MM"
    display_name: str | None = None
    score: int


class LeaderboardResponse(BaseModel):
    """Monthly leaderboard: top entries, the caller's own standing, and recent
    winners. Score = likes*1 + comments*3 + 5 per post (self-engagement excluded)."""

    month: str  # current month, "YYYY-MM"
    entries: list[LeaderboardEntry]
    my_rank: int | None = None
    my_score: int = 0
    recent_winners: list[PastWinner] = Field(default_factory=list)
