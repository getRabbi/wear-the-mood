# ENV MATRIX — variable names by service (Phase 0)

> **Names only — never values.** `SECRET` = must be set via Heroku config vars / Azure Container Apps secret refs / dashboards, never in Git.
> Source: `backend/app/core/config.py`, the live droplet `backend/.env` / `.env` / `admin-web/.env.production` key names, and `docker-compose.yml`.
> Target service legend: **API**=Heroku `wtm-api-prod`/`-staging` · **RBG**=Azure `wtm-rembg-worker` · **ORC**=Azure `wtm-ai-orchestrator` · **CRON**=Azure scheduled jobs · **REC**=Azure `wtm-recovery` · **ADMIN**=`wtm-admin`.

## Core runtime

| Name | Secret | API | RBG | ORC | CRON | REC | Notes |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| `ENVIRONMENT` | | ✅ | ✅ | ✅ | ✅ | ✅ | `prod`/`staging` |
| `APP_NAME` | | ✅ | | | | | |
| `LOG_LEVEL` | | ✅ | ✅ | ✅ | ✅ | ✅ | |
| `API_V1_PREFIX` | | ✅ | | | | | `/v1` |
| `PORT` / `$PORT` | | ✅ | | | | | Heroku injects `$PORT` |
| `ALLOWED_ORIGINS` | | ✅ | | | | | CORS |
| `GIT_SHA` | | ✅ | ✅ | ✅ | ✅ | ✅ | build metadata (surface in `/readyz`) |
| `WEB_CONCURRENCY` | | ✅ | | | | | Heroku: `1` (512 MB) |

## Supabase / database

| Name | Secret | API | RBG | ORC | CRON | REC | Notes |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| `SUPABASE_URL` | | ✅ | ✅ | ✅ | ✅ | ✅ | new US project URL (Phase 3) |
| `SUPABASE_ANON_KEY` | | ✅ | | | | | JWKS `apikey` header |
| `SUPABASE_SERVICE_ROLE_KEY` | 🔑 | ✅ | ✅ | ✅ | ✅ | | Storage REST + service ops |
| `SUPABASE_JWT_SECRET` | 🔑 | ✅ | | | | | HS256 fallback verify |
| `CONNECTION_STRING` | 🔑 | ✅ | ✅ | ✅ | ✅ | ✅ | **runtime DSN → Session Pooler 5432** (was 6543); `statement_cache_size=0` |
| `CONNECTION_STRING_DIRECT` | 🔑 | | | | ✅ | | migrations/admin + `backup` cron (direct 5432; pg_dump can't use pooler) |

## AI / providers

| Name | Secret | API | RBG | ORC | CRON | Notes |
|---|:--:|:--:|:--:|:--:|:--:|---|
| `TRYON_PROVIDER` | | ✅ | | ✅ | | `fashn` in prod |
| `FASHN_API_KEY` | 🔑 | | | ✅ | | |
| `FASHN_BASE_URL`, `FASHN_MODEL` | | | | ✅ | | |
| `BG_PROVIDER` | | | ✅ | | | `rembg` on worker |
| `IMAGEGEN_PROVIDER`, `IMAGEGEN_MOCK` | | | | ✅ | | AI Studio enhance |
| `ANTHROPIC_API_KEY` | 🔑 | | | ✅ | ✅ | tagging/stylist/news |
| `ANTHROPIC_MODEL_STYLIST/VISION/NEWS/ROUTINE` | | | | ✅ | ✅ | |
| `OPENAI_API_KEY` | 🔑 | | | ✅ | ✅ | embeddings/moderation/fallback |
| `OPENAI_EMBEDDING_MODEL`, `OPENAI_MODERATION_MODEL`, `OPENAI_MODEL_CHAT` | | | | ✅ | ✅ | |
| `LLM_PRIMARY` | | ✅ | | ✅ | ✅ | `openai` in prod |
| `WEATHER_PROVIDER`, `OPEN_METEO_BASE_URL` | | ✅ | | | | stylist context |

## Storage / media (Cloudflare R2)

| Name | Secret | API | RBG | ORC | CRON | Notes |
|---|:--:|:--:|:--:|:--:|:--:|---|
| `R2_ENDPOINT` | | ✅ | ✅ | ✅ | ✅ | |
| `R2_ACCESS_KEY_ID` | 🔑 | ✅ | ✅ | ✅ | ✅ | |
| `R2_SECRET_ACCESS_KEY` | 🔑 | ✅ | ✅ | ✅ | ✅ | |
| `R2_PUBLIC_BUCKET`, `R2_PRIVATE_BUCKET`, `*_STAGING` | | ✅ | ✅ | ✅ | ✅ | |
| `R2_PUBLIC_BASE_URL` | | ✅ | ✅ | ✅ | | `cdn.wearthemood.com` |
| `R2_SIGNED_URL_TTL` | | ✅ | | ✅ | | |
| `STORAGE_WRITES` | | ✅ | ✅ | ✅ | | **`legacy` today** (media on Supabase Storage) |
| `BACKUP_KEEP` | | | | | ✅ | backup cron retention |

## Subscriptions / notifications / observability / limits

| Name | Secret | API | ORC | CRON | Notes |
|---|:--:|:--:|:--:|:--:|---|
| `REVENUECAT_WEBHOOK_AUTH` | 🔑 | ✅ | | | `POST /v1/billing/webhook` |
| `REVENUECAT_API_KEY` | 🔑 | ✅ | | | optional verify |
| `PUSH_PROVIDER` | | ✅ | | ✅ | `fcm` in prod |
| `FCM_PROJECT_ID` | | ✅ | | ✅ | |
| `FCM_CREDENTIALS_JSON` | 🔑 | ✅ | | ✅ | service-account JSON |
| `DAILY_PUSH_HOUR` | | | | ✅ | daily-push cron |
| `SENTRY_DSN` | 🔑 | ✅ | ✅ | ✅ | ✅ |
| `POSTHOG_API_KEY` | 🔑 | ✅ | | | |
| `POSTHOG_HOST` | | ✅ | | | |
| `NEWS_PROVIDER`, `NEWS_RSS_FEEDS` | | | | ✅ | news cron (`rss`) |
| `FREE_TRYON_TRIAL_CREDITS` | | ✅ | | | |
| `DAILY_COST_ALERT_USD` | | | | ✅ | spend-alert cron |
| `REFERRAL_*` (enabled, bonus, window, base/play URLs) | | ✅ | | | server-controlled |
| `REFERRAL_HASH_SECRET` | 🔑 | ✅ | | | falls back to JWT secret |
| `AFFILIATE_*` (`AFFILIATE_TAG` secret-ish) | ~ | ✅ | | | unset today |

## admin-web (`wtm-admin`)

| Name | Secret | Notes |
|---|:--:|---|
| `SUPABASE_SERVICE_ROLE_KEY` | 🔑 | server-only direct reads |
| `FASTAPI_BASE_URL` | | → Heroku API |
| `ADMIN_PANEL_BASE_PATH` | | `/mood-ops-console-7x9` |
| `ADMIN_IP_ALLOWLIST` | | ingress allowlist |
| `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` | | build args (public) |

## NEW — queue/worker vars added in Phase 2 (§11.2)

| Name | Secret | RBG | ORC | REC | Notes |
|---|:--:|:--:|:--:|:--:|---|
| `QUEUE_PROVIDER` | | ✅ | ✅ | ✅ | `azure` \| `stub` |
| `AZURE_STORAGE_ACCOUNT_NAME` | | ✅ | ✅ | ✅ | managed identity preferred |
| `AZURE_STORAGE_QUEUE_ENDPOINT` | | ✅ | ✅ | ✅ | |
| `AZURE_STORAGE_CONNECTION_STRING` | 🔑 | ✅ | ✅ | ✅ | fallback only |
| `AZURE_QUEUE_JOBS`, `AZURE_QUEUE_ENRICHMENT` | | ✅ | ✅ | ✅ | `jobs`, `enrichment` |
| `QUEUE_MESSAGE_VERSION`, `WORKER_MAX_ATTEMPTS`, `WORKER_STALE_SECONDS` | | ✅ | ✅ | ✅ | defaults: 1 / 5 / — |
| `EMERGENCY_API_ENABLED` | | | | | emergency ACA app guard (`false`) |
| `MAINTENANCE_MODE` | | ✅ | | | off by default |

## Drift — droplet keys NOT read by current backend config (`extra="ignore"`)

`PHOTOROOM_API_KEY`, `REMOVE_BG_API_KEY`, `BG_REMOVAL_PROVIDER`, `OPENAI_MODEL_FALLBACK`, `google_auth_id`, `google_auth_secret` — legacy/unused by `config.py`. Do **not** carry forward blindly; confirm with founder (Google OAuth is configured in the Supabase dashboard, not consumed here).

**Root `.env` (Caddy/compose interpolation, not needed on Heroku/Azure):** `API_DOMAIN`, `ADMIN_PANEL_BASE_PATH`, `ADMIN_SUPABASE_URL`, `ADMIN_SUPABASE_ANON_KEY`.
