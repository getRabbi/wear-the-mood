from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.llm.base import Embedder, GarmentTagger
from app.services.llm.stub import StubEmbedder, StubGarmentTagger


@lru_cache
def get_garment_tagger() -> GarmentTagger:
    """Resolve the garment tagger (CLAUDE.md §2.1). Claude vision when an
    Anthropic key is set; stub otherwise (CI/api/local)."""
    settings = get_settings()
    if is_secret_set(settings.anthropic_api_key):
        from app.services.llm.anthropic_tagger import AnthropicGarmentTagger

        return AnthropicGarmentTagger(settings.anthropic_api_key, settings.anthropic_model_vision)
    return StubGarmentTagger()


@lru_cache
def get_embedder() -> Embedder:
    """Resolve the embedder (CLAUDE.md §2.1). OpenAI text-embedding-3-small when
    an OpenAI key is set; stub (no-op) otherwise."""
    settings = get_settings()
    if is_secret_set(settings.openai_api_key):
        from app.services.llm.openai_embedder import OpenAIEmbedder

        return OpenAIEmbedder(settings.openai_api_key, settings.openai_embedding_model)
    return StubEmbedder()
