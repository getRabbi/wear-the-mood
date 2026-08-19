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


class GarmentFidelityFinding(BaseModel):
    """One way a render failed to be the garment the user actually chose.

    `code` is a STABLE identifier so rejections are countable across releases;
    `detail` is free text for the log line and never reaches a user.
    """

    code: str
    detail: str | None = None


class GarmentFidelityReport(BaseModel):
    """Whether a rendered look still shows the SELECTED garments (§19, §29).

    Deliberately about identity, not pixels. Pose, folds, lighting and drape all
    change between a flat garment photo and the same garment worn by a person —
    a similarity threshold tight enough to notice a top becoming a shirt would
    reject most correct renders. So the question asked is categorical: is this
    the same KIND of garment, in the same colour, with the same sleeve and
    hem length and the same print, still present on the body.
    """

    #: True only when the judge positively confirmed the garment survived.
    faithful: bool = True
    findings: list[GarmentFidelityFinding] = Field(default_factory=list)
    input_tokens: int | None = None
    output_tokens: int | None = None


class GarmentFidelityJudge(ABC):
    name: str

    @abstractmethod
    async def compare(
        self,
        *,
        garment: bytes,
        garment_media_type: str,
        render: bytes,
        render_media_type: str,
        canonical: str,
    ) -> GarmentFidelityReport:
        """Judge whether [render] still shows the garment in [garment], or raise.

        Raising means "could not judge", which is NOT the same as "unfaithful"
        and must never be reported as one — see the fidelity service for how an
        unjudgeable render is handled.
        """
        raise NotImplementedError
