"""OpenAI text embedder (CLAUDE.md §2.1) — Apache-2.0 SDK, commercial API.

text-embedding-3-small (1536-d) for wardrobe semantic search + the taste graph,
stored as pgvector. Lazy-imports the openai SDK (worker-only dep).
"""

from __future__ import annotations

from app.services.llm.base import Embedder


class OpenAIEmbedder(Embedder):
    name = "openai"
    dimensions = 1536

    def __init__(self, api_key: str, model: str) -> None:
        from openai import AsyncOpenAI

        # Bounded timeout + a single retry so a slow embedding call can't stall the
        # single worker loop. Embedding is best-effort enrichment (CLAUDE.md §2.1).
        self._client = AsyncOpenAI(api_key=api_key, timeout=20.0, max_retries=1)
        self._model = model

    async def embed(self, text: str) -> list[float]:
        resp = await self._client.embeddings.create(model=self._model, input=text)
        return resp.data[0].embedding
