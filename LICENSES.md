# LICENSES

Every third-party dependency, model, and external service used by Fashion OS, with its license.

**Hard rule (CLAUDE.md §2.2):** Before adding ANY library or model, record it here. This is a **commercial** build — use only permissive (MIT / Apache-2.0 / BSD) or properly licensed dependencies. Flag anything **NC (non-commercial) / GPL / restricted** to the founder BEFORE using it.

**Status legend:** `planned` = intended for this phase, not yet installed · `in-use` = present in `pubspec.yaml` / `requirements.txt` · License is re-confirmed against the resolved package version at install time.

---

## Flutter / Dart (`app/`)

| Package | License | Status | Purpose |
|---|---|---|---|
| flutter (SDK) | BSD-3-Clause | planned | Mobile framework |
| flutter_riverpod / riverpod_annotation | MIT | planned | State management |
| riverpod_generator | MIT | planned | Provider codegen (dev) |
| go_router | BSD-3-Clause | planned | Routing + deep links |
| freezed / freezed_annotation | MIT | planned | Immutable models |
| json_serializable / json_annotation | BSD-3-Clause | planned | JSON (de)serialization |
| build_runner | BSD-3-Clause | planned | Codegen runner (dev) |
| google_fonts | Apache-2.0 | planned | Fraunces / Inter type |
| dio | MIT | planned | HTTP client |
| supabase_flutter | MIT | planned | Auth / DB / storage / realtime |
| flutter_secure_storage | BSD-3-Clause | planned | Secure token storage *(confirm at install)* |
| cached_network_image | MIT | planned | Image caching |
| photo_view | MIT | planned | Zoomable images |
| flutter_animate | MIT | planned | Motion |
| flutter_image_compress | MIT | planned | Pre-upload compression |
| sentry_flutter | MIT | planned | Crash/error reporting |
| posthog_flutter | MIT | planned | Analytics |
| purchases_flutter (RevenueCat) | MIT | planned | Subscriptions/IAP |

## Python / FastAPI (`backend/`)

| Package | License | Status | Purpose |
|---|---|---|---|
| fastapi | MIT | planned | Web framework |
| uvicorn | BSD-3-Clause | planned | ASGI server |
| pydantic | MIT | planned | Schemas/validation |
| python-dotenv | BSD-3-Clause | planned | Env loading |
| httpx | BSD-3-Clause | planned | Async HTTP (provider calls) |
| supabase (python) | MIT | planned | Supabase client |
| sentry-sdk | MIT | planned | Error reporting |
| posthog (python) | MIT | planned | Analytics |
| ruff | MIT | planned | Lint/format (dev) |
| pytest | MIT | planned | Tests (dev) |
| anthropic | MIT | planned | Claude provider *(confirm at install)* |
| openai | Apache-2.0 | planned | OpenAI provider + embeddings *(confirm at install)* |
| rembg | MIT | planned | Background removal (launch quality) |

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
