from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed application settings, loaded from environment + a git-ignored
    `.env` file (run the app from the `backend/` directory). Secret keys live
    only in `.env*`, never in `.env.example` (CLAUDE.md §11).
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # Runtime
    environment: str = "dev"
    app_name: str = "Fashion OS API"
    log_level: str = "INFO"
    api_v1_prefix: str = "/v1"
    port: int = 8000
    allowed_origins: str = "http://localhost:3000"

    # Supabase (real values come from .env)
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    supabase_jwt_secret: str = ""
    connection_string: str = ""

    # Observability
    sentry_dsn: str = ""

    # Credits / limits (CLAUDE.md §12)
    free_daily_tryon_credits: int = 5

    # Background removal (CLAUDE.md §2.2). 'stub' everywhere except the Render
    # worker, which sets BG_PROVIDER=rembg (heavy model, lazy-imported there).
    bg_provider: str = "stub"

    # Try-on provider (CLAUDE.md §2.2). Routed to FASHN only when a key is set;
    # otherwise the stub keeps the job lifecycle runnable.
    tryon_provider: str = "stub"
    fashn_api_key: str = ""
    fashn_base_url: str = "https://api.fashn.ai"
    fashn_model: str = "tryon-v1.6"

    # Weather (CLAUDE.md §2) — Open-Meteo is free + keyless, so it is the default
    # provider; set WEATHER_PROVIDER=stub for offline/CI/deterministic runs.
    weather_provider: str = "open_meteo"
    open_meteo_base_url: str = "https://api.open-meteo.com"

    # LLM providers (CLAUDE.md §2.1). Routed by real-key presence (placeholders
    # ignored); the worker does tagging + embeddings, so keys live in its env.
    anthropic_api_key: str = ""
    anthropic_model_vision: str = "claude-haiku-4-5-20251001"
    openai_api_key: str = ""
    openai_embedding_model: str = "text-embedding-3-small"
    openai_moderation_model: str = "omni-moderation-latest"

    @property
    def allowed_origins_list(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def is_prod(self) -> bool:
        return self.environment == "prod"


def is_secret_set(value: str) -> bool:
    """True only for a real secret — empty or `.env.example` placeholder values
    (``your-...``, ``sk-...xxxx``) count as unset so a copied template never
    accidentally activates a provider with a fake key."""
    v = (value or "").strip().lower()
    return bool(v) and not v.startswith("your") and "xxxx" not in v and v != "sk-ant-xxxxxxxx"


@lru_cache
def get_settings() -> Settings:
    return Settings()
