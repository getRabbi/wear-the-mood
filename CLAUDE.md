# CLAUDE.md — Fashion OS — Production Build Blueprint (v3, FINAL)

> Single source of truth for building **Fashion OS**, a company-grade cross-platform fashion app.
> Read this entire file before any task. Build phase-by-phase, small commits, production discipline.
> When a rule here conflicts with a quick hack, the rule wins. Ask one focused question if blocked, then proceed.

---

## 0. How we work (human + Claude Code)

- The **founder** (solo, based in Bangladesh) runs you (Claude Code) inside VS Code on Windows. **Android-first**: develops/tests on Android (real device preferred), launches Android first, then borrows a Mac + uses Codemagic to ship iOS once there's traction.
- **You (Claude Code)** write code, follow this blueprint, and end every task with: (a) a manual test checklist, (b) a suggested conventional-commit message, (c) any new env vars added.
- **Strategy/architecture** decisions happen in chat with the founder; **implementation** happens here.
- Founder's working language is Banglish; code, comments, and docs you write are clean English.

---

## 1. Product Vision

A **personal fashion OS** — the app a style-conscious person opens daily to decide what to wear, see clothes on themselves before buying, manage what they own, and join a style community.

**Funnel (memorize — every feature serves it):**
`AI try-on HOOK -> digital wardrobe UTILITY -> daily AI stylist HABIT -> social COMMUNITY -> news/commerce MONETIZATION`

The try-on is the match; the wardrobe + stylist + community are the fire. **Do not over-engineer try-on quality. Invest in the daily-use loop, the data moat, and design polish.**

Five pillars:
1. **Profile + AI try-on** (hook): avatar from selfie + body data; render any garment (new or owned) on the user.
2. **Digital wardrobe** ("digital almira"): every owned item digitized, organized, mix-and-matchable. The core data asset.
3. **AI stylist** (habit): "what do I wear today?" from real wardrobe + weather + calendar + learned taste.
4. **Social** (community/virality): outfit-of-the-day, follow, feedback, challenges, group styling.
5. **Fashion news & commerce**: industry feed, trends, drops, trend-to-closet, shop-the-look.

Category rollout: clothing (men/women/babies) -> shoes/glasses/accessories -> beyond.

---

## 2. Tech Stack (do not deviate without asking)

| Layer | Choice | Notes |
|---|---|---|
| Mobile | **Flutter (Dart)** | iOS + Android, one codebase. Founder knows Dart. **Android-first.** |
| State | **Riverpod** (+ riverpod_generator) | Typed, testable providers. No global mutable singletons. |
| Routing | **go_router** | Declarative, deep-link ready. |
| Models | **freezed** + **json_serializable** | Immutable typed models, no hand-written JSON. |
| Backend | **FastAPI** (Python 3.11+), async | AI orchestration + business logic + credit metering. |
| **Backend hosting** | **DigitalOcean droplet (docker-compose)** | ONE droplet runs api + worker + the crons (`ofelia`) + Caddy (HTTPS) via `docker-compose.yml`; Supabase stays the managed DB. **Deploy is manual** (`ssh` → `git pull` → `docker compose up -d --build`) — NOT auto on push. See `DEPLOY_DIGITALOCEAN.md`. `render.yaml` is kept only as a fallback (do not assume Render is live). |
| DB/Auth/Storage/Realtime | **Supabase** (Postgres) | **Start on the FREE tier; upgrade to Pro when usage/users require it** (watch DB size, storage, monthly active users, egress). RLS on every user table. |
| Job queue | **Supabase + the docker-compose `worker`** to start, **Redis + Arq/RQ** at scale | Async try-on jobs (section 7). |
| Subscriptions | **RevenueCat** (Flutter SDK) | Wraps Google Play Billing (first) + App Store (later). Backend verifies entitlement. |
| Web payments (later) | **Lemon Squeezy / Paddle** (merchant of record) | For any web-based subscription/checkout — handles Bangladesh payout + tax. |
| Image storage/CDN | **Cloudflare R2 + CDN** (or Supabase Storage to start) | Signed upload URLs. |
| Push | **Firebase Cloud Messaging** | + local notifications for the daily stylist. |
| Weather | **Open-Meteo** (free, no key) or OpenWeatherMap | For stylist context. |
| Analytics | **PostHog** | Event taxonomy in section 15. |
| Error/crash | **Sentry** (Flutter + FastAPI) | From Phase 0. |
| Remote config / flags | **PostHog feature flags** (or Supabase table) | Gate every new feature (section 16). |

### 2.1 AI providers — BOTH OpenAI and Anthropic (abstracted)

All LLM/vision calls go behind an `LLMProvider` interface in `backend/app/services/llm/`. Route by task, with fallback:

| Task | Primary | Fallback / alt | Why |
|---|---|---|---|
| Stylist chat (nuanced) | **Claude Sonnet** | GPT-4-class | Strong instruction-following, persona consistency. |
| Routine suggestions / classification | **Claude Haiku** | GPT-mini-class | Cheap, fast; use prompt caching. |
| Garment auto-tagging (vision) | **Claude vision** or **GPT vision** | the other | Cross-check accuracy; pick cheaper per volume. |
| Embeddings (taste graph, wardrobe semantic search) | **OpenAI text-embedding-3-small** | — | Cheap, strong; store as pgvector in Postgres. |
| Content moderation reasoning | **Claude** | GPT | For UGC + try-on inputs (section 19). |

Rules: never hardcode a provider in a router or widget; always go through `LLMProvider`. Per-task model is env-configurable. Retry + timeout + fallback-to-secondary on 5xx/overload. Log token usage + USD cost per call (section 14).

### 2.2 Open-source leverage (use, don't reinvent) — WITH LICENSE CARE

**Background removal** (wardrobe item cutout):
- **Start:** `rembg` (Python, MIT) — pip-installable, wraps U2Net/ISNet; fine for clean product shots; weak on hair/lace.
- **Production quality:** **BiRefNet** (Apache-2.0, commercial OK) — SOTA edges/hair/fabric. On HuggingFace (`ZhengPeng7/BiRefNet`), usable via recent `rembg` (>= 2.0.59).
- **Alt:** **BEN2** base model (MIT, commercial OK) — excellent hair matting.
- **AVOID for commercial without a license:** **Bria RMBG-2.0/1.4** — weights need a Bria commercial agreement.

**Virtual try-on** (the hook):
- **Launch with FASHN.ai API** ($0.075/image) — clean commercial terms, no GPU ops, swappable.
- **Self-host later to cut cost — LICENSE IS CRITICAL:**
  - **Leffa** (MIT) — commercial-friendly. **Preferred self-host option.**
  - **AVOID — CatVTON:** CC BY-NC-SA 4.0 = **NON-COMMERCIAL. Do NOT ship commercially.**
  - **VERIFY first — IDM-VTON / OOTDiffusion:** research/non-commercial style weight licenses.
- Track new models via GitHub `Zheng-Chong/Awesome-Try-On-Models`.

**Other useful OSS:** SAM/SAM2 (masks if needed), MediaPipe (on-device pose/face landmarks, Apache-2.0), `flutter_image_compress`, `cached_network_image`, `photo_view`, `flutter_animate`.

**Hard rule:** Before adding ANY model/library, record its license in `LICENSES.md`. Commercial build = permissive (MIT/Apache/BSD) or properly licensed only. Flag anything NC/GPL to the founder BEFORE using it.

---

## 3. Project Structure

```
fashionos/
├── CLAUDE.md
├── LICENSES.md                  # every dependency + its license (keep current)
├── app/                         # Flutter
│   ├── lib/
│   │   ├── main.dart
│   │   ├── bootstrap.dart        # env, Sentry, providers init
│   │   ├── l10n/                 # localized strings (English now, structured for i18n)
│   │   ├── core/
│   │   │   ├── theme/            # design system (section 4)
│   │   │   ├── router/           # go_router + deep links
│   │   │   ├── env/              # env config (no secrets in code)
│   │   │   ├── network/          # dio client, interceptors, error mapping
│   │   │   └── analytics/        # PostHog wrapper, event names
│   │   ├── data/
│   │   │   ├── models/           # freezed models
│   │   │   ├── repositories/     # one per domain
│   │   │   └── sources/          # supabase + api clients (+ local cache)
│   │   ├── features/
│   │   │   ├── onboarding/  auth/  profile/  tryon/  wardrobe/
│   │   │   ├── stylist/  social/  news/  paywall/
│   │   └── shared/
│   │       ├── widgets/          # reusable UI (buttons, cards, states)
│   │       └── utils/
│   ├── test/                     # unit + widget + golden tests
│   └── pubspec.yaml
├── backend/                     # FastAPI
│   ├── app/
│   │   ├── main.py
│   │   ├── core/                # config, supabase_auth, credits, rate_limit, idempotency, logging
│   │   ├── routers/             # v1/* : tryon, wardrobe, stylist, news, social, profile, billing
│   │   ├── services/
│   │   │   ├── tryon/  bg/  llm/  news/  moderation/  weather/
│   │   ├── models/              # pydantic schemas
│   │   ├── workers/             # async job processing (docker-compose worker)
│   │   ├── cron/                # scheduled jobs (daily push) — run by ofelia (docker-compose)
│   │   └── tests/
│   ├── requirements.txt
│   └── .env.example
└── supabase/
    ├── migrations/              # ordered, versioned SQL migrations (section 6)
    └── FASHIONOS_BASELINE.sql   # consolidated baseline (founder's single-file pattern)
```

---

## 4. Design System & Modern UI (a core deliverable)

**Aesthetic:** editorial, minimal, image-forward — a modern fashion magazine app. Generous whitespace, refined neutral palette + one accent, smooth motion, no clutter. Photos are the hero; UI recedes.

### 4.1 Design tokens (`core/theme/tokens.dart`)

```dart
import 'package:flutter/material.dart';

/// Design tokens — the ONLY place raw values live. Never hardcode colors/sizes in widgets.
abstract class AppColors {
  static const ink        = Color(0xFF1A1A1A);
  static const graphite   = Color(0xFF6B6B6B);
  static const mist        = Color(0xFFE7E4DF);
  static const paper       = Color(0xFFFAF8F5);
  static const surface     = Color(0xFFFFFFFF);
  static const inkDark     = Color(0xFFF2F0EC);
  static const paperDark   = Color(0xFF121212);
  static const surfaceDark = Color(0xFF1C1C1C);
  static const accent      = Color(0xFFB44C2E); // terracotta — one signature color
  static const accentSoft  = Color(0xFFF0D9CF);
  static const success = Color(0xFF3F7D52);
  static const warn    = Color(0xFFC9A227);
  static const danger  = Color(0xFFB23B3B);
}
abstract class AppSpace  { static const xs=4.0, sm=8.0, md=16.0, lg=24.0, xl=32.0, xxl=48.0; }
abstract class AppRadius { static const sm=8.0, md=14.0, lg=22.0, pill=999.0; }
abstract class AppShadow { static const card=[BoxShadow(color: Color(0x14000000), blurRadius:24, offset: Offset(0,8))]; }
abstract class AppMotion {
  static const fast=Duration(milliseconds:180), base=Duration(milliseconds:280), slow=Duration(milliseconds:480);
  static const easing=Curves.easeOutCubic;
}
```

### 4.2 Typography & ThemeData (`core/theme/app_theme.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'tokens.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark()  => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark    = b == Brightness.dark;
    final ink     = dark ? AppColors.inkDark : AppColors.ink;
    final paper   = dark ? AppColors.paperDark : AppColors.paper;
    final surface = dark ? AppColors.surfaceDark : AppColors.surface;
    final display = GoogleFonts.fraunces(); // editorial headers
    final body    = GoogleFonts.inter();    // UI/body

    final text = TextTheme(
      displaySmall:  display.copyWith(fontSize:30, height:1.1,  color:ink, fontWeight:FontWeight.w600),
      headlineSmall: display.copyWith(fontSize:22, height:1.15, color:ink),
      titleMedium:   body.copyWith(fontSize:16, fontWeight:FontWeight.w600, color:ink),
      bodyMedium:    body.copyWith(fontSize:15, height:1.45, color:ink),
      labelLarge:    body.copyWith(fontSize:14, fontWeight:FontWeight.w600, letterSpacing:.2),
      bodySmall:     body.copyWith(fontSize:13, color: dark ? AppColors.mist : AppColors.graphite),
    );

    return ThemeData(
      useMaterial3: true, brightness: b, scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: b, surface: surface),
      textTheme: text,
      dividerColor: dark ? const Color(0xFF2A2A2A) : AppColors.mist,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent, foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
          textStyle: text.labelLarge,
        ),
      ),
      cardTheme: CardThemeData(color: surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg))),
    );
  }
}
```

### 4.3 UI rules (enforce everywhere)
- **Never hardcode** color/size/radius/spacing — use tokens.
- Every screen handles **four states**: loading (shimmer), empty (illustration + CTA), error (retry), content. No bare spinner.
- Tap targets >= 48dp; respect safe areas; support text scaling.
- Motion via `AppMotion`; hero transition on the try-on reveal. Subtle, never bouncy.
- Dark mode first-class. One accent color only.
- Images: `cached_network_image` + token placeholder + fade-in; compress on upload (section 8).
- Reusable kit in `shared/widgets/`: `PrimaryButton`, `AppCard`, `EmptyState`, `ErrorState`, `LoadingShimmer`, `AppChip`, `OutfitTile`.
- **All user-facing strings go through `l10n/`** (English now), so i18n is free later. Never inline raw strings.

### 4.4 Accessibility
Semantic labels on interactive elements/images. WCAG AA contrast. Don't rely on color alone. Dynamic type. Screen-reader pass once per phase.

---

## 5. Data Model (Supabase)

Baseline in `FASHIONOS_BASELINE.sql`; later changes as ordered migrations (section 6). RLS ON for every user-owned table.

Tables: `profiles`, `credits`, `wardrobe_items` (`embedding vector`, `last_worn_at`, `wear_count`, `cost`, `purchase_date`), `outfits`, `tryon_jobs` (async), `tryon_results`, `posts`, `follows`, `likes`, `comments`, `news_items`, `taste_signals`, `idempotency_keys`, `ai_usage_log`, `consents`, `reports` (UGC reports), `feature_flags`.

RLS: own-row read/write for profiles, credits, wardrobe_items, outfits, tryon_*, taste_signals, consents. Social tables read-public, write-own. `news_items` read-public. `ai_usage_log`/`idempotency_keys` service-role only.

Use **pgvector** for `wardrobe_items.embedding` + taste vectors -> semantic closet search + taste matching.

---

## 6. Migrations & environments

- **Three environments:** `dev` (local/personal Supabase), `staging`, `prod`. Never test on prod.
- Keep `FASHIONOS_BASELINE.sql` as canonical baseline; every later change is an **ordered, idempotent migration** in `supabase/migrations/NNNN_description.sql`. Test on staging before prod.
- **Set the app bundle/package id once** (`com.fashionos.app`) — it can NEVER change after store publish. Pick carefully now.
- Secrets per environment in env/CI secrets, never in git.
- **Supabase scaling:** start FREE; upgrade to Pro before hitting free-tier limits (DB size, storage, MAU, egress, or when you need daily backups / no project pausing). Set a reminder to check usage monthly.

---

## 7. Async jobs (try-on is NOT synchronous)

Try-on takes ~5–20s; blocking requests time out. Pattern:
1. App `POST /v1/tryon` with **idempotency key** (section 9) -> backend checks credits + moderates input (section 19) -> creates `tryon_jobs` (`status=queued`), enqueues, returns `{job_id}` (202).
2. **The worker** (docker-compose service) calls TryOnProvider, stores result, sets `status=done|failed`.
3. App subscribes via **Supabase Realtime** on `tryon_jobs` (or polls `GET /v1/tryon/{job_id}`), shows progress, then hero-reveals.
4. Credits decrement **on success only**; never charge on failure. Wrap in a transaction.

Same pattern for batch wardrobe import + video reels. Simple worker first; Redis + Arq/RQ at scale.

---

## 8. Image handling
- Compress before upload (`flutter_image_compress`): ~1600px long edge, JPEG/WebP, < ~500KB wardrobe.
- **Strip EXIF** on upload (privacy).
- Upload via **signed URL** straight to storage (don't proxy big files through FastAPI).
- Store original (short retention), cutout, result; serve via CDN + cache headers; make grid thumbnails.
- Server-side validate: file-type allow-list, max size, dimension caps.
- **Cache wardrobe locally** so the closet is viewable offline (read-only) — sync on reconnect.

---

## 9. Idempotency & double-charge protection
Every credit-spending / job-creating endpoint requires an `Idempotency-Key` header (UUID per user action). Backend stores keys + response in `idempotency_keys`; a repeat key returns the stored response instead of re-charging/re-working. Guards against double-taps, retries, flaky networks.

---

## 10. Privacy, consent, legal, account lifecycle (selfies + body data = sensitive)
- **Explicit consent before any face/body capture** -> `consents` (type, version, timestamp). Block avatar/try-on until consented.
- Body/face may be **biometric** (BIPA US / GDPR special category): minimize collection, **auto-delete raw try-on inputs after processing** (~72h like FASHN), never sell identifiable data.
- **In-app account deletion + data export are MANDATORY** (Google Play requires in-app account deletion if accounts can be created; GDPR requires export + erasure). Build a "Delete my account & data" flow in Phase 1.
- Ship: Privacy Policy + ToS + biometric notice (hosted URLs — needed for store listings); age gate (consider 18+ at launch like Google's Doppl to reduce risk).
- Any future anonymized trend/fit data: aggregate + anonymized + opt-in only.
- Never log PII or tokenized URLs in plaintext.

---

## 11. Security
- Verify Supabase JWT on every protected route (`core/supabase_auth.py`); derive user_id from token, never trust client.
- Tokens in **flutter_secure_storage**; 401 -> silent refresh -> retry interceptor.
- All AI/3rd-party keys **backend-only**; the app never holds FASHN/OpenAI/Anthropic keys.
- RLS as defense-in-depth; signed expiring storage URLs; validate all input; rate limit (section 12).
- Secrets in env/CI; `.env` git-ignored; ship `.env.example`.

---

## 12. Rate limiting & abuse
- Per-user + per-IP limits on AI endpoints (token bucket / Supabase counter to start).
- Free tier: small daily credit bucket (e.g. 3–5 try-ons/day), enforced **server-side**.
- Detect abuse (rapid-fire, multi-account/device); CAPTCHA / Play Integrity / App Attest on signup if needed. Alert on cost spikes (section 14).

---

## 13. Versioned API & error contract
- All routes under `/v1/`; never break a shipped client (additive or new version only).
- Uniform error JSON: `{ "error": { "code": "INSUFFICIENT_CREDITS", "message": "...", "request_id": "..." } }`. App maps `code` -> localized friendly message.
- Codes: `UNAUTHENTICATED`, `INSUFFICIENT_CREDITS`, `RATE_LIMITED`, `PROVIDER_ERROR`, `VALIDATION_ERROR`, `MODERATION_BLOCKED`, `NOT_FOUND`.

---

## 14. Observability & cost control (AI cost runaway is risk #1)
- Log every AI call to `ai_usage_log`: user, provider, model, tokens/images, **estimated USD**, latency, success.
- Daily cost dashboard + **alert** above a spend threshold.
- Sentry (app + backend) from Phase 0; carry `request_id` end-to-end.
- Cost levers: prompt caching + batch; cheap models for routine; self-host BiRefNet (bg removal) then Leffa (try-on) at scale.

---

## 15. Analytics & event taxonomy (PostHog, from day one)
Naming `noun_verb`, snake_case. Core events: `app_opened`, `onboarding_completed`, `consent_granted`, `avatar_created`, `tryon_started`, `tryon_succeeded`, `tryon_shared`, `wardrobe_item_added`, `outfit_created`, `stylist_queried`, `daily_suggestion_opened`, `post_created`, `post_liked`, `user_followed`, `challenge_joined`, `paywall_viewed`, `trial_started`, `subscription_started`, `affiliate_link_clicked`, `referral_sent`, `account_deleted`. Powers funnel/retention/virality + monetization tuning.

---

## 16. Feature flags
Every new feature ships behind a flag (PostHog / `feature_flags` table): gradual rollout, kill-switch, A/B tests (paywall copy, free-credit count, onboarding variants).

---

## 17. Onboarding & the "aha" moment
- Goal: first **try-on result within ~60 seconds** = activation.
- Flow: 3-screen value carousel -> permission priming (explain before OS prompt) -> consent -> quick avatar -> first try-on (free credits) -> hero reveal -> add first wardrobe item -> soft account create.
- Don't gate the first wow behind signup. Delay the hard paywall until after activation.

---

## 18. Monetization hooks (in code)
- Entitlements via RevenueCat; backend verifies for premium actions; never trust client entitlement.
- Contextual paywalls (flagged): after free credits exhausted, unlimited wardrobe, advanced stylist, HD/video reels.
- Pricing config remote (flags), not hardcoded; pre-select annual; long trial (14–17 days converts better).
- Affiliate deep links with attribution on shop-the-look / closet-gap; log `affiliate_link_clicked`.
- **Android billing first** (Google Play Billing via RevenueCat); App Store billing wired at iOS launch; web checkout via Lemon Squeezy/Paddle later.

---

## 19. Content & input moderation (CRITICAL — abuse vector)
A "put clothes on a body" tool WILL be misused. Required safeguards:
- **Moderate try-on INPUT images** before processing: reject nudity/minors/non-consensual or clearly abusive uploads (vision moderation). Return `MODERATION_BLOCKED`. This is not optional — it protects users, the app, and the founder legally.
- **Moderate social UGC** (posts/comments) before public: nudity/abuse/banned content; queue uncertain cases; user reporting (`reports`) + block. Gradual social rollout.
- Keep a clear acceptable-use policy; log moderation decisions.

---

## 20. Notifications
- **Android 13+ requires runtime notification permission** — prompt contextually (after first value), not on launch.
- Daily stylist push fires at the **user's local morning** — store timezone, schedule per-timezone (don't blast everyone at one UTC time / 3am).
- Use FCM for remote, local notifications for scheduled. Respect opt-out.

---

## 21. Testing & CI/CD
- **Tests:** unit (repositories, credit/idempotency, provider wrappers with mocked AI), widget (key screens), golden (design components), backend pytest (mocked providers). Don't chase 100% — cover money paths (credits, billing, idempotency, moderation) + core flows.
- **CI:** GitHub Actions — lint (`dart analyze`, `ruff`), format, test on every PR.
- **CD:** **Codemagic** -> Android build (also local) + iOS build (cloud, no Mac needed). **Backend deploy is MANUAL** to the DigitalOcean droplet (`ssh` -> `git pull` -> `docker compose up -d --build`); pushing to main does NOT deploy it. See `DEPLOY_DIGITALOCEAN.md`.
- **Monthly iOS compile-check on Codemagic from Phase 1** (even pre-iOS-launch) so platform issues surface early, not as 50 errors on launch day.
- Branching: `main` (deployable) <- short-lived feature branches. Conventional commits.

---

## 22. Store launch prep (Android first, iOS later)
Treat as real tasks, not afterthoughts — these block launch:
- **Developer accounts:** Google Play ($25 one-time) now; Apple ($99/yr) at iOS launch.
- **Google Play closed-testing requirement:** new personal developer accounts must run a closed test with **~12–20 testers for ~14 days** before production access. **Start recruiting testers early** (Phase 2) so this doesn't delay launch.
- **Store assets:** app icon, feature graphic, screenshots (per device size), short/full description, category, contact, **hosted Privacy Policy + ToS URLs**.
- **Play Data Safety form + biometric/data declarations** — fill accurately (face/body data); inaccurate declarations = rejection/removal.
- **Payouts from Bangladesh:** confirm Google Play (and later Apple) payout to a supported BD bank/payment method; use Lemon Squeezy/Paddle (merchant of record) for any web subscriptions to simplify BD payout + tax.
- Versioning: bump `version+build` every release; keep a changelog.

---

## 23. Build phases (founder requests these in order)
- **Phase 0 — Foundations (wk 1–2):** repos; Flutter + FastAPI skeleton; Supabase baseline + RLS (free tier); auth (**Google + email first**; Apple Sign-In deferred to pre-iOS); secure storage + refresh; design system (section 4); l10n scaffold; Sentry + PostHog; backend services (api/worker/cron) via docker-compose on a DigitalOcean droplet; `.env.example`; `LICENSES.md`; CI.
- **Phase 1 — Hook + Wardrobe = launchable MVP (wk 3–9):** consent + onboarding; avatar + body data; async try-on (FASHN) with jobs/idempotency/credits + **input moderation**; wardrobe add -> bg removal -> tagging -> embedding; closet grid (4 states, offline cache); outfit builder; watermarked share; **account deletion + data export**; paywall scaffold (off).
- **Phase 2 — Stylist + Social = public launch (wk 10–15):** Claude/OpenAI stylist (wardrobe + weather + taste signals); morning daily-suggestion push (timezone-aware, Android 13+ permission); OOTD post, feed, like, comment, follow; UGC moderation + reporting; first challenge; **recruit Play closed-testers.**
- **Phase 3 — News + Commerce (mo 4–6):** news feed (RSS+API, summarized); trend-to-closet; shop-the-look affiliate; subscription live (Google Play Billing via RevenueCat; contextual paywalls; trial).
- **Phase 4 — Depth (mo 6–9):** wardrobe analytics (cost-per-wear, ROI); closet gap analysis; packing planner; calendar autopilot; referral loop; shareable try-on reels (video).
- **Phase 5 — Expansion (mo 9–18):** shoes/glasses/accessories; resale nudges/integration; group styling rooms; creator tools; **iOS launch** (borrowed Mac + Codemagic); in-source bg removal (BiRefNet) / try-on (Leffa) to cut COGS.

**Do NOT build yet:** custom diffusion training, native AR, precise biometric body scanning, multi-language UI (just scaffold l10n), web app beyond marketing/public-closet pages.

---

## 24. Unique / moat features (slot into phases)
Try-on reels (P4); Taste Graph "Style DNA" via embeddings (P2+); cost-per-wear + Wardrobe ROI (P4); challenges & streaks (P2+); closet gap analysis -> shoppable (P4); trend-to-closet (P3); packing planner (P4); group styling rooms (P5, viral invites); calendar autopilot (P4); resale nudges (P5). Each must serve engagement, retention, or virality.

---

## 25. Engineering rules (Definition of Done + anti-patterns)

**Definition of Done:**
1. Follows structure & naming. 2. Typed (freezed/pydantic), no stray `dynamic`. 3. Four UI states handled. 4. Errors handled + mapped. 5. Tokens used (no hardcoded styles). 6. AI behind provider wrapper; credits + idempotency + input moderation on paid/AI actions. 7. Analytics events fired. 8. Behind a flag if new. 9. Test for money/core paths. 10. Strings via l10n. 11. Manual test checklist + commit message provided.

**Never:** call third-party AI directly from Flutter; put business logic in widgets; hardcode secrets/prices/colors/sizes/strings; trust client user_id or entitlement; charge credits before success; skip try-on input moderation; ship a screen with only a spinner; add an NC/GPL model to the commercial build; break a shipped `/v1` contract; skip consent before biometric capture; change the bundle id after publish.

**Always ask the founder before:** adding a dependency, changing the data model, changing the stack, adding an AI provider, or anything touching billing or biometric data.
