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

    @property
    def allowed_origins_list(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def is_prod(self) -> bool:
        return self.environment == "prod"


@lru_cache
def get_settings() -> Settings:
    return Settings()
