from __future__ import annotations

from app.services.llm.base import Embedder, GarmentTagger, GarmentTags


class StubGarmentTagger(GarmentTagger):
    """No-op tagger (CI/api/local without a key). Returns empty tags so the
    enrichment pipeline runs without overwriting anything."""

    name = "stub"

    async def tag(self, image: bytes, media_type: str) -> GarmentTags:
        return GarmentTags()


class StubEmbedder(Embedder):
    """No-op embedder — returns a zero vector of the right shape so the pipeline
    runs without a key."""

    name = "stub"
    dimensions = 1536

    async def embed(self, text: str) -> list[float]:
        return [0.0] * self.dimensions
