"""LLM/vision task interfaces (CLAUDE.md §2.1).

All LLM/vision calls go through these — never call a vendor SDK from a router or
worker. Concrete providers (Anthropic vision for tagging, OpenAI for embeddings)
are chosen by env in the get_* resolvers, with a stub default so CI/api/local
need no key. Token usage rides back on the result for cost logging (§14).
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from pydantic import BaseModel, Field


class GarmentTags(BaseModel):
    """Structured attributes auto-extracted from a garment photo (§2.1)."""

    category: str | None = None
    subcategory: str | None = None
    color: str | None = None
    pattern: str | None = None
    tags: list[str] = Field(default_factory=list)
    input_tokens: int | None = None
    output_tokens: int | None = None


class GarmentTagger(ABC):
    name: str

    @abstractmethod
    async def tag(self, image: bytes, media_type: str) -> GarmentTags:
        """Return structured tags for a single-garment image, or raise."""
        raise NotImplementedError


class Embedder(ABC):
    name: str
    dimensions: int

    @abstractmethod
    async def embed(self, text: str) -> list[float]:
        """Return the embedding vector for [text], or raise."""
        raise NotImplementedError
