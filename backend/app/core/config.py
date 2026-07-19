from collections.abc import Mapping
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
    # Deployed commit SHA, surfaced by /health so we can tell WHAT code is live
    # (manual deploys can drift). Set in the droplet env, e.g. GIT_SHA=$(git rev-parse HEAD).
    git_sha: str = ""
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

    # Queue bridge (blueprint §11.2). 'stub' in-memory everywhere except the Azure
    # workers/api which set 'azure' (+ managed identity, or a connection-string
    # fallback). Messages are wake signals only; Postgres stays authoritative (§4.2).
    queue_provider: str = "stub"  # stub | azure
    azure_storage_account_name: str = ""
    azure_storage_queue_endpoint: str = ""
    azure_storage_connection_string: str = ""  # SECRET fallback; prefer managed identity
    azure_queue_jobs: str = "jobs"
    azure_queue_enrichment: str = "enrichment"
    queue_message_version: int = 1
    worker_max_attempts: int = 5  # §4.4 default maximum attempts before poison-fail
    worker_stale_seconds: int = 300  # lease/stale threshold before recovery re-signals

    # Finite-batch policy for the event-driven Container Apps JOBS (Phase 5 §B).
    # Jobs bill per execution, so an execution must terminate; these bound it.
    # Tunable from measured results — see PHASE_5_REPORT.md before changing.
    batch_max_seconds: int = 180  # wall-clock budget per execution
    batch_idle_exit_seconds: int = 10  # exit once the queue stays empty this long
    rembg_batch_max_jobs: int = 10  # amortises the one-time model load
    orchestrator_batch_max_jobs: int = 20  # lighter per-job work -> larger batch

    # Maintenance mode (§11.9) — blocks mutating endpoints with a retryable response;
    # /healthz and /readyz stay up. Off by default.
    maintenance_mode: bool = False
    # Emergency API (§4, §11.8) — `emergency_api` marks THIS instance as the ACA
    # break-glass app; it refuses all traffic unless `emergency_api_enabled` is set.
    # Prod/staging leave both false (never gated by the emergency guard).
    emergency_api: bool = False
    emergency_api_enabled: bool = False

    # Credits / limits (CLAUDE.md §12, §18). The free AI try-on grant is a
    # ONE-TIME trial (total, not per-day): after this many AI try-ons a free user
    # hits the paywall. 2D try-on is always free + client-side.
    free_tryon_trial_credits: int = 3

    # Referral reward — LEGACY manual-code redemption (§24), both sides. Kept for
    # the orphaned legacy /v1/referrals/redeem path; the new install-attribution
    # program below supersedes it.
    referral_reward_credits: int = 5

    # Referral rewards program (install-attribution, §24). SERVER-CONTROLLED — the
    # app never sends these. Referrer earns a persistent (top-up) bonus once a
    # genuinely new account claims via a Play-install-attributed token; the
    # referred user earns 0 in this version. Attribution tokens live 30 days.
    referral_enabled: bool = True
    referral_referrer_bonus_credits: int = 10
    referral_referred_bonus_credits: int = 0
    referral_attribution_window_days: int = 30
    # Small clock/transaction tolerance when checking that the referred account was
    # created AFTER the referral click (guards the App-Link-on-fresh-signup path).
    referral_new_account_tolerance_seconds: int = 300
    # Public base for share links + the Play redirect target (com.fashionos.app).
    referral_public_base_url: str = "https://wearthemood.com"
    referral_play_store_url: str = (
        "https://play.google.com/store/apps/details?id=com.fashionos.app"
    )
    # HMAC key for hashing per-install ids before storage. Falls back to the JWT
    # secret (always set in prod) so install hashes are never rainbow-table-able.
    referral_hash_secret: str = ""

    # Background removal (CLAUDE.md §2.2). 'stub' everywhere except the Render
    # worker, which sets BG_PROVIDER=rembg (heavy model, lazy-imported there).
    bg_provider: str = "stub"

    # Try-on provider (CLAUDE.md §2.2). Routed to FASHN only when a key is set;
    # otherwise the stub keeps the job lifecycle runnable.
    tryon_provider: str = "stub"
    fashn_api_key: str = ""
    fashn_base_url: str = "https://api.fashn.ai"
    fashn_model: str = "tryon-v1.6"

    # AI Studio image enhancer (BUILD_PROMPT_PRO_PROMAX.md — AI Enhance Item). FASHN
    # does TRY-ON, not flat-garment enhancement, so there is no provider wired yet:
    # the default 'stub' returns a clear PROVIDER_ERROR ("not configured") in prod
    # and NEVER fakes output. Set IMAGEGEN_MOCK=true in DEV ONLY to make the stub
    # echo its input (so the full flow is exercisable without a real provider).
    imagegen_provider: str = "stub"  # stub | (future: real enhancer)
    imagegen_mock: bool = False
    # Catalog Model Shot reuses the TRY-ON provider (garment on a studio model). It
    # is live only when a catalog model preset has a real image (tryon_model_presets,
    # kind='catalog', is_active=true); otherwise it fails cleanly (no fake output).

    # Weather (CLAUDE.md §2) — Open-Meteo is free + keyless, so it is the default
    # provider; set WEATHER_PROVIDER=stub for offline/CI/deterministic runs.
    weather_provider: str = "open_meteo"
    open_meteo_base_url: str = "https://api.open-meteo.com"

    # News ingestion (CLAUDE.md §1 pillar 5). 'stub' until the founder picks
    # sources; 'rss' reads NEWS_RSS_FEEDS (needs feedparser in the cron service).
    news_provider: str = "stub"  # stub | rss
    news_rss_feeds: str = ""  # comma-separated feed URLs

    # Subscriptions / entitlements (CLAUDE.md §18). RevenueCat REST key (optional
    # on-demand verify) + the shared secret that authenticates its webhook.
    revenuecat_api_key: str = ""
    revenuecat_webhook_auth: str = ""

    # Shop-the-look affiliate links (CLAUDE.md §18, §24). Backend-only + remote-
    # swappable; unset => a neutral web search (no attribution).
    affiliate_provider: str = ""
    affiliate_search_url: str = ""  # e.g. https://www.retailer.com/search
    affiliate_query_param: str = "q"
    affiliate_tag_param: str = ""  # e.g. tag / utm_source
    affiliate_tag: str = ""  # the affiliate id (SECRET-ish; backend only)

    # Push notifications (CLAUDE.md §20). 'stub' logs and no-ops everywhere; the
    # push/cron service sets 'fcm' once the founder's Firebase creds are present.
    push_provider: str = "stub"  # stub | fcm
    fcm_project_id: str = ""
    fcm_credentials_json: str = ""  # service-account JSON (SECRET)
    daily_push_hour: int = 8  # local hour the morning stylist push fires (§20)

    # Image storage / CDN — Cloudflare R2 (CLAUDE.md §2, §8; INFRA_UPGRADE Ph.1).
    # S3-compatible; keys are backend-only (§11). Buckets are environment-isolated
    # so prod images stay separate: dev/staging use the *_STAGING buckets. Public
    # objects get a stable CDN URL (r2_public_base_url); private objects are served
    # ONLY via short-lived signed URLs (r2_signed_url_ttl). Nothing writes to R2
    # until the upload paths are wired (Commit 3); this is config + the provider.
    r2_endpoint: str = ""
    r2_access_key_id: str = ""
    r2_secret_access_key: str = ""
    r2_public_bucket: str = ""
    r2_private_bucket: str = ""
    r2_public_bucket_staging: str = ""
    r2_private_bucket_staging: str = ""
    r2_public_base_url: str = ""  # CDN custom domain for the PUBLIC bucket
    r2_signed_url_ttl: int = 3600  # seconds; private GET URLs expire

    # Migration WRITE-GATE (INFRA_UPGRADE Phase 1B). 'legacy' = new images keep
    # going to the existing Supabase Storage; 'r2' = new images write to R2 via the
    # media StorageProvider. Reads resolve PER-RECORD either way, so flipping this
    # is safe + reversible once 1C has backfilled bytes. Default legacy = NO
    # behavior change; flip to 'r2' only after staging verification.
    storage_writes: str = "legacy"  # legacy | r2

    # Nightly DB backup (Phase 4B). pg_dump -> private R2 bucket under
    # backups/<env>/; keep the most recent N dumps. Needs CONNECTION_STRING_DIRECT
    # (pg_dump can't run through the 6543 transaction pooler).
    backup_keep: int = 7

    # AI cost guardrail (§14). The spend-alert cron warns (log + Sentry) when the
    # last 24h of ai_usage_log spend reaches this; 0 disables the alert.
    daily_cost_alert_usd: float = 25.0

    # LLM providers (CLAUDE.md §2.1). Routed by real-key presence (placeholders
    # ignored); the worker does tagging + embeddings, so keys live in its env.
    anthropic_api_key: str = ""
    anthropic_model_vision: str = "claude-haiku-4-5-20251001"
    anthropic_model_stylist: str = "claude-sonnet-4-6"  # nuanced stylist chat (§2.1)
    anthropic_model_news: str = "claude-haiku-4-5-20251001"  # cheap summaries (§2.1)
    openai_api_key: str = ""
    openai_embedding_model: str = "text-embedding-3-small"
    openai_moderation_model: str = "omni-moderation-latest"
    openai_model_chat: str = "gpt-4o-mini"  # OpenAI fallback for text tasks (§2.1)

    # Which LLM leads the text tasks (stylist/news/packing); the other is the
    # automatic fallback (§2.1). Both run only if their key is set; stub backs
    # the router. Leave 'anthropic' to auto-fall-back to OpenAI when Claude fails.
    llm_primary: str = "anthropic"  # anthropic | openai

    @property
    def allowed_origins_list(self) -> list[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def news_rss_feeds_list(self) -> list[str]:
        return [f.strip() for f in self.news_rss_feeds.split(",") if f.strip()]

    @property
    def is_prod(self) -> bool:
        return self.environment == "prod"

    @property
    def referral_hmac_key(self) -> str:
        """The key used to HMAC per-install ids before storage. Prefers the
        dedicated secret; falls back to the JWT secret so it is always set."""
        return self.referral_hash_secret.strip() or self.supabase_jwt_secret

    @property
    def r2_configured(self) -> bool:
        """True only when the R2 connection + public CDN base are really set
        (placeholders don't count) — gates whether R2 can be used at all."""
        return (
            is_secret_set(self.r2_endpoint)
            and is_secret_set(self.r2_access_key_id)
            and is_secret_set(self.r2_secret_access_key)
            and bool(self.r2_public_base_url.strip())
        )

    @property
    def active_public_bucket(self) -> str:
        """The public bucket for THIS environment — prod uses the live bucket,
        dev/staging use the -staging bucket so real images stay isolated."""
        if self.is_prod:
            return self.r2_public_bucket
        return self.r2_public_bucket_staging or self.r2_public_bucket

    @property
    def active_private_bucket(self) -> str:
        if self.is_prod:
            return self.r2_private_bucket
        return self.r2_private_bucket_staging or self.r2_private_bucket

    @property
    def r2_writes_enabled(self) -> bool:
        """True only when the gate is flipped AND R2 is really configured — so a
        half-set env can never silently send writes into the void."""
        return self.storage_writes.lower() == "r2" and self.r2_configured


def is_secret_set(value: str) -> bool:
    """True only for a real secret — empty or `.env.example` placeholder values
    (``your-...``, ``sk-...xxxx``) count as unset so a copied template never
    accidentally activates a provider with a fake key."""
    v = (value or "").strip().lower()
    return bool(v) and not v.startswith("your") and "xxxx" not in v and v != "sk-ant-xxxxxxxx"


def pick_migration_dsn(env: Mapping[str, str | None]) -> tuple[str | None, bool]:
    """Choose the DSN for migrations / admin SCRIPTS (never runtime). Prefer the
    DIRECT 5432 connection (``CONNECTION_STRING_DIRECT``); fall back to the runtime
    6543 transaction pooler (``CONNECTION_STRING``) when the direct one is absent so
    existing workflows keep working (DDL runs fine on the pooler — Phase 2B).

    Returns ``(dsn, used_fallback)``; ``dsn`` is None when neither is set. The
    runtime DB pool (app/core/db.py) is unaffected — it always uses the 6543
    ``CONNECTION_STRING``.
    """
    direct = (env.get("CONNECTION_STRING_DIRECT") or "").strip()
    if direct:
        return direct, False
    pooled = (env.get("CONNECTION_STRING") or "").strip()
    return (pooled or None), True


@lru_cache
def get_settings() -> Settings:
    return Settings()
