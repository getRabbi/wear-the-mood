from functools import lru_cache

from app.core.config import get_settings, is_secret_set
from app.services.llm.base import GarmentTagger
from app.services.llm.stub import StubGarmentTagger


@lru_cache
def get_garment_tagger() -> GarmentTagger:
    """Resolve the garment tagger (CLAUDE.md §2.1). Claude vision when an
    Anthropic key is set; stub otherwise (CI/api/local). The embedder resolver
    lands with the embeddings step."""
    settings = get_settings()
    if is_secret_set(settings.anthropic_api_key):
        from app.services.llm.anthropic_tagger import AnthropicGarmentTagger

        return AnthropicGarmentTagger(settings.anthropic_api_key, settings.anthropic_model_vision)
    return StubGarmentTagger()
