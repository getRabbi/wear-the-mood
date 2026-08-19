from __future__ import annotations

from app.services.llm.base import (
    Embedder,
    GarmentFidelityJudge,
    GarmentFidelityReport,
    GarmentTagger,
    GarmentTags,
)


class StubGarmentTagger(GarmentTagger):
    """No-op tagger (CI/api/local without a key). Returns empty tags so the
    enrichment pipeline runs without overwriting anything."""

    name = "stub"

    async def tag(self, image: bytes, media_type: str) -> GarmentTags:
        return GarmentTags()


class StubFidelityJudge(GarmentFidelityJudge):
    """No judge configured (CI/api/local without a key).

    Raises rather than returning `faithful=True`. "Nobody looked" and "somebody
    looked and it was fine" are different facts, and a stub that answered the
    second one would silently report 100% fidelity coverage in an environment
    with no vision provider at all — which is precisely the false assurance this
    gate exists to remove. The caller turns this into `unverified`.
    """

    name = "stub"

    async def compare(
        self,
        *,
        garment: bytes,
        garment_media_type: str,
        render: bytes,
        render_media_type: str,
        canonical: str,
    ) -> GarmentFidelityReport:
        raise NotImplementedError("no fidelity judge is configured")


class StubEmbedder(Embedder):
    """No-op embedder — returns a zero vector of the right shape so the pipeline
    runs without a key."""

    name = "stub"
    dimensions = 1536

    async def embed(self, text: str) -> list[float]:
        return [0.0] * self.dimensions
