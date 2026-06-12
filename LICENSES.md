# LICENSES

Every third-party dependency, model, and external service used by Fashion OS, with its license.

**Hard rule (CLAUDE.md §2.2):** Before adding ANY library or model, record it here. This is a **commercial** build — use only permissive (MIT / Apache-2.0 / BSD) or properly licensed dependencies. Flag anything **NC (non-commercial) / GPL / restricted** to the founder BEFORE using it.

**Status legend:** `planned` = intended for this phase, not yet installed · `in-use` = present in `pubspec.yaml` / `requirements.txt` · License is re-confirmed against the resolved package version at install time.

---

## Flutter / Dart (`app/`)

| Package | License | Status (resolved version) | Purpose |
|---|---|---|---|
| flutter (SDK) | BSD-3-Clause | in-use (3.44.1) | Mobile framework |
| cupertino_icons | MIT | in-use (1.0.8) | iOS-style icons |
| flutter_localizations | BSD-3-Clause | in-use (SDK) | i18n delegates |
| intl | BSD-3-Clause | in-use (0.20.2) | Message formatting for l10n |
| flutter_riverpod | MIT | in-use (3.3.1) | State management |
| riverpod_annotation | MIT | in-use (4.0.2) | Provider codegen annotations |
| go_router | BSD-3-Clause | in-use (17.3.0) | Routing + deep links |
| freezed_annotation | MIT | in-use (3.1.0) | Immutable model annotations |
| json_annotation | BSD-3-Clause | in-use (4.12.0) | JSON annotations |
| google_fonts | Apache-2.0 | in-use (8.1.0) | Fraunces / Inter type |
| dio | MIT | in-use (5.9.2) | HTTP client |
| supabase_flutter | MIT | in-use (2.14.1) | Auth / DB / storage / realtime |
| flutter_secure_storage | BSD-3-Clause | in-use (10.3.1) | Secure token storage |
| cached_network_image | MIT | in-use (3.4.1) | Image caching |
| sentry_flutter | MIT | in-use (8.14.2) | Crash/error reporting |
| posthog_flutter | MIT | in-use (5.26.0) | Analytics |
| _dev:_ build_runner | BSD-3-Clause | in-use (2.15.0) | Codegen runner |
| _dev:_ riverpod_generator | MIT | in-use (4.0.4-dev.1 ⚠️ pre-release) | Provider codegen |
| _dev:_ freezed | MIT | in-use (3.2.6-dev.1 ⚠️ pre-release) | Model codegen |
| _dev:_ json_serializable | BSD-3-Clause | in-use (6.14.0) | JSON codegen |
| _dev:_ flutter_lints | BSD-3-Clause | in-use (6.0.0) | Lint rules |
| photo_view | MIT | planned (Phase 1) | Zoomable images |
| flutter_animate | MIT | planned (Phase 1) | Motion |
| flutter_image_compress | MIT | in-use (2.4.0) | Pre-upload compression + EXIF strip (§8) |
| image_picker | BSD-3-Clause | in-use (1.2.2) | Camera/gallery capture for wardrobe add (§8) |
| url_launcher | BSD-3-Clause | in-use (6.3.2) | Open Privacy/ToS/acceptable-use links (§10, §19, §22) |
| purchases_flutter (RevenueCat) | MIT | planned (Phase 3) | Subscriptions/IAP |

> ⚠️ **Pre-release codegen note:** `freezed` and `riverpod_generator` resolved to maintainer pre-release builds because Dart 3.12 / Flutter 3.44 is very new and the matching stable codegen isn't published yet. Both are pinned in `app/pubspec.lock` (reproducible). Revisit when stable releases land.

## Python / FastAPI (`backend/`)

| Package | License | Status | Purpose |
|---|---|---|---|
| fastapi | MIT | in-use (0.136.3) | Web framework |
| uvicorn[standard] | BSD-3-Clause | in-use (0.49.0) | ASGI server |
| starlette | BSD-3-Clause | in-use (1.2.1, via fastapi) | ASGI toolkit |
| pydantic | MIT | in-use (2.13.4) | Schemas/validation |
| pydantic-settings | MIT | in-use (2.14.1) | Typed env settings |
| python-dotenv | BSD-3-Clause | in-use (1.2.2) | .env loading |
| PyJWT | MIT | in-use (2.13.0) | Verify Supabase JWTs (§11) |
| asyncpg | Apache-2.0 | in-use (0.31.0) | Async Postgres (transactional money-paths) |
| httpx | BSD-3-Clause | in-use (0.28.1) | Async HTTP (worker: image download + Storage upload) + test client |
| _dev:_ ruff | MIT | in-use (0.15.16) | Lint/format |
| _dev:_ pytest | MIT | in-use (9.0.3) | Tests |
| _dev:_ pyyaml | MIT | in-use (6.0.3) | Parse render.yaml in tests |
| _dev/ops:_ psycopg[binary] | **LGPL-3.0** ⚠️ | in-use (3.3.4) | DB migration applier — see note |
| supabase (python) | MIT | planned (Step 9) | Supabase client |
| sentry-sdk | MIT | in-use (2.61.1) | Error reporting |
| posthog (python) | MIT | planned (Step 10) | Analytics |
| anthropic | MIT | in-use — worker only (>=0.40.0) | Claude vision garment tagging (§2.1) |
| feedparser | BSD-2-Clause | in-use — cron only (>=6.0.0) | RSS/Atom parsing for the news ingestion cron (§1 pillar 5) |
| openai | Apache-2.0 | in-use (2.41.0) | text-embedding-3-small — item + search-query embeddings (§2.1) |
| rembg[cpu] | MIT | in-use — worker only (>=2.0.59) | Background removal (requirements-worker.txt; BG_PROVIDER=rembg) |
| onnxruntime | MIT | in-use — worker only (via rembg) | Model inference backend for rembg |
| pillow | HPND (permissive) | in-use — worker only (>=10.0.0) | Image I/O for rembg |

> ⚠️ **psycopg (LGPL-3.0):** the only non-permissive dependency. Acceptable because it's a **dev/ops** tool (applies SQL migrations) used **unmodified** and **never shipped** in the mobile app — LGPL permits this commercially. If we ever need a Postgres driver inside shipped/distributed code, re-evaluate (or use a permissive driver).

## AI models / external services

| Name | License / Terms | Status | Notes |
|---|---|---|---|
| FASHN.ai API | Commercial API (ToS) | planned | Try-on at launch (~$0.075/img); behind provider wrapper |
| OpenAI `text-embedding-3-small` | Commercial API (ToS) | planned | Taste/wardrobe embeddings → pgvector |
| BiRefNet (`ZhengPeng7/BiRefNet`) | Apache-2.0 ✅ commercial OK | future | Self-host bg removal to cut COGS |
| BEN2 (base) | MIT ✅ commercial OK | future | Alt bg removal, strong hair matting |
| Leffa | MIT ✅ commercial OK | future | **Preferred** self-host try-on |
| MediaPipe | Apache-2.0 | future | On-device pose/face landmarks |
| SAM / SAM2 | Apache-2.0 *(verify)* | future | Masks if needed |

## ⛔ AVOID (non-commercial / restricted — do NOT ship)

| Name | License | Why blocked |
|---|---|---|
| CatVTON | CC BY-NC-SA 4.0 | **Non-commercial** — cannot ship commercially |
| Bria RMBG-2.0 / 1.4 | Bria commercial agreement required | Weights need a paid Bria license |
| IDM-VTON / OOTDiffusion | Research / NC-style weights | **Verify** before any use; assume restricted |
