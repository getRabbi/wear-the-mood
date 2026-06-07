# Fashion OS

A personal **fashion OS** — AI try-on, a digital wardrobe, a daily AI stylist, a style community, and fashion news/commerce. The app a style-conscious person opens daily to decide what to wear.

> **Single source of truth:** [`CLAUDE.md`](./CLAUDE.md). Read it in full before any work.
> Companion setup/workflow notes (Banglish): [`SETUP_AND_WORKFLOW.md`](./SETUP_AND_WORKFLOW.md).

**Funnel:** AI try-on `HOOK` → digital wardrobe `UTILITY` → daily AI stylist `HABIT` → social `COMMUNITY` → news/commerce `MONETIZATION`.

---

## Monorepo layout

```
/                       repo root (this folder)
├── app/                Flutter app  (Android-first; iOS later via Codemagic)
├── backend/            FastAPI service (AI orchestration, credits, business logic)
├── supabase/
│   ├── FASHIONOS_BASELINE.sql   canonical schema baseline (+ RLS)
│   └── migrations/              ordered, idempotent SQL migrations
├── CLAUDE.md           build blueprint (authoritative)
├── LICENSES.md         every dependency + its license (keep current)
└── SETUP_AND_WORKFLOW.md
```

## Fixed decisions (do not change casually)

- **Bundle / package id:** `com.fashionos.app` — **permanent**, can never change after store publish.
- **Android-first.** Auth: **Google + email first** (Apple Sign-In deferred to pre-iOS). Billing: **Google Play via RevenueCat** first.
- **Supabase free tier** to start; **RLS on every user-owned table**.
- **All AI / 3rd-party keys are backend-only** — the Flutter app never holds them.
- Hosting: **Render** (api + worker + cron). DB/Auth/Storage/Realtime: **Supabase**.

## Local prerequisites

- **Flutter SDK** (stable channel) + Dart (bundled) — verify with `flutter doctor`
- **Android Studio** (Android SDK + an emulator/AVD) or a real Android device
- **Python 3.11+**
- **Git**
- *(optional)* Node + Supabase CLI for DB tooling

> iOS builds require a Mac; planned via **Codemagic** cloud later. Windows cannot build iOS locally.

## Build order

Phase-by-phase per [`CLAUDE.md` §23](./CLAUDE.md). Currently: **Phase 0 — Foundations.**

## Conventions

- **Branches:** `main` is always deployable. Short-lived `feat/*`, `fix/*`, `chore/*` branches off `main`.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`, `build:`.
- **Environments:** `dev`, `staging`, `prod`. Never test on prod. Secrets live in env / CI only — never committed.
- Generated Dart (`*.g.dart`, `*.freezed.dart`) is git-ignored; run `dart run build_runner build` after pulling.
