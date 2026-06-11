from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class PostCreate(BaseModel):
    """Create an OOTD post (CLAUDE.md §1 pillar 4). A post needs visible content
    — an image (e.g. a try-on result or outfit cover) and/or one of the user's
    own outfits."""

    caption: str | None = Field(default=None, max_length=2000)
    image_url: str | None = Field(default=None, max_length=2000)
    outfit_id: UUID | None = None

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
