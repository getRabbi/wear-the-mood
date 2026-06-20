# Fashion OS — Activation & Launch Runbook

The codebase is **feature-complete behind stubs** (Phases 0–3 done; Phase 4 is 5/6).
Every paid/external integration degrades gracefully, so you can turn things on in
any order. This is the ordered path from "works on stubs" to "live in the Play
Store". Do the steps top-to-bottom; each section says **who** acts and **why**.

Legend: 🔵 = founder action (accounts/keys/$, can't be automated) · 🟢 = done in
the repo already · ⚙️ = a command you (or Claude) run.

---

## 0. What's already done 🟢

- Backend (FastAPI) + Flutter app, all five pillars + depth features, **243 backend
  + 137 app tests green**, lint/format clean.
- Supabase **dev** schema live (baseline + migrations `0001`–`0009`, 23 tables, RLS on all).
- `render.yaml` blueprint (api + worker + daily-push cron + news cron).
- Legal page **drafts** in `legal/` (privacy + biometric notice, terms, acceptable-use).
- FASHN try-on verified live; OpenAI + Anthropic keys present in dev `.env`.

---

## 1. Production Supabase 🔵⚙️

1. 🔵 Create a **prod** Supabase project (separate from dev). Keep it on Free until
   usage requires Pro (watch DB size / storage / MAU / egress).
2. 🔵 Copy the prod `CONNECTION_STRING`, `SUPABASE_URL`, anon + service-role keys,
   `SUPABASE_JWT_SECRET` into a local `backend/.env.prod` (git-ignored).
3. ⚙️ Apply the schema **in order** (idempotent):
   ```
   cd backend
   python scripts/apply_sql.py ../supabase/FASHIONOS_BASELINE.sql
   python scripts/apply_sql.py ../supabase/migrations/0001_wardrobe_storage.sql
   # …through 0009 (run each in numeric order)
   ```
   Then create the storage buckets the migrations reference (wardrobe, avatars) if
   not auto-created, and confirm RLS is on for all tables.

> Never test against prod. Keep dev/staging/prod separate (CLAUDE.md §6).

## 2. Deploy the backend 🔵⚙️

**Recommended: DigitalOcean droplet** (always-on, ≈free for a year on your credit) —
one 2 GB box runs api + worker + crons + HTTPS via Docker. Full steps in
**`DEPLOY_DIGITALOCEAN.md`** (create droplet → `git clone` → `backend/.env` →
`docker compose up -d --build`). Supabase stays the DB.

Alternative: **Render** (`render.yaml`) — zero-ops but the free tier sleeps the api
(cold starts) and the worker/crons are paid (~$21/mo for the full set):

1. 🔵 New → **Blueprint** → point at this repo. Render reads `render.yaml`.
2. 🔵 Fill the **`fashionos-shared`** env group + per-service `sync:false` keys in the
   dashboard (Supabase, `CONNECTION_STRING`, AI keys, etc.). Use the **prod** values.
3. Bring services up in this order, verifying each:
   - **api** (free) → check `GET /v1/health` is 200.
   - **worker** (starter) → unblocks bg-removal cutouts + embeddings → **lights up
     wardrobe search + trend-to-closet**.
   - **daily** cron → push (stub until Firebase, §4).
   - **news** cron → set `NEWS_PROVIDER=rss` + `NEWS_RSS_FEEDS` (validated set is in
     `backend/.env.example`).
4. 🔵 Point the app's API base URL at the prod api host (Flutter env config).

## 3. AI providers 🔵

- **Anthropic — OUT OF CREDITS.** Top up at console.anthropic.com → Plans & Billing.
  Until then the stylist, news summaries, garment tagging, packing, and calendar all
  fall back to deterministic stubs (nothing breaks, but no real Claude output).
- **OpenAI** — confirm the key has credits → embeddings (search + trend-to-closet).
- **FASHN** — already verified live.

## 4. Push notifications (Firebase) 🔵🟢

1. 🔵 Create a Firebase project; add the Android app (`com.fashionos.app`); download
   `google-services.json` into `app/android/app/`.
2. 🔵 Generate a service-account JSON → set `FCM_CREDENTIALS_JSON` + `FCM_PROJECT_ID`
   + `PUSH_PROVIDER=fcm` on the **daily** cron; `pip install firebase-admin` is needed
   there (add to requirements when you enable it; record Apache-2.0 in LICENSES.md).
3. 🟢→ Claude: wire the Flutter `firebase_messaging` client (token registration to
   `PUT /v1/profile/push-token`, Android-13 permission, `/stylist` deep-link). *Gated
   on step 1 — ask Claude to build it once `google-services.json` exists.*

## 5. Subscriptions (RevenueCat + Play Billing) 🔵🟢

1. 🔵 RevenueCat account + project; create the subscription products in **Play Console**;
   wire them as RevenueCat offerings. **Set RevenueCat's app_user_id = the Supabase
   user id** (the webhook relies on this).
2. 🔵 Set `REVENUECAT_API_KEY` + `REVENUECAT_WEBHOOK_AUTH` on the api; point the
   RevenueCat webhook at `POST /v1/billing/webhook` with that same Authorization value.
3. 🟢→ Claude: add the `purchases_flutter` SDK + the real purchase/restore flow.
   *Gated on step 1.*

## 6. Shop-the-look affiliate 🔵

🔵 Sign up an affiliate program (Amazon Associates / RewardStyle-LTK / Rakuten) →
set `AFFILIATE_SEARCH_URL`, `AFFILIATE_TAG_PARAM`, `AFFILIATE_TAG` on the api. Until
then "Shop" links go to a neutral web search (no attribution).

## 7. Legal pages 🔵

🔵 Have a lawyer review `legal/privacy.md`, `legal/terms.md`, `legal/acceptable-use.md`,
fill the `{{PLACEHOLDERS}}`, and **host** them at the exact URLs the app links to:
`https://wearthemood.com/legal/{privacy,terms,acceptable-use}`. **Required** for the
Play listing + the Data Safety form. (16+ stated in the policy + Play target audience; biometric declaration. No in-app age gate.)

## 8. Observability 🔵

🔵 Set `SENTRY_DSN` (api + worker) and `POSTHOG_API_KEY` so errors + the funnel
events flow. Set a daily AI-cost alert (CLAUDE.md §14).

## 9. Android launch 🔵

1. 🔵 Google Play developer account ($25). New personal accounts must run a **closed
   test with ~12–20 testers for ~14 days** before production — **start recruiting now**.
2. 🔵 Store assets: icon, feature graphic, screenshots, descriptions, category, the
   hosted Privacy Policy URL, and the **Data Safety** form (declare face/body data
   accurately — inaccurate = rejection).
3. ⚙️ Build a release APK/AAB (Codemagic or local). Confirm Play payouts work for
   Bangladesh.

## 10. iOS (later) 🔵

Borrow a Mac + Codemagic; add Apple Sign-In + the $99/yr account. (Run a monthly iOS
compile-check on Codemagic now so issues surface early — CLAUDE.md §21.)

---

## Minimum viable launch (the short path)

To get a usable Android beta out fastest:

1. Prod Supabase + schema (§1)
2. Deploy **api + worker** to Render (§2) — skip crons initially
3. Top up Anthropic + confirm OpenAI (§3)
4. Host the legal pages (§7)
5. Sentry + PostHog DSNs (§8)
6. Play account + closed test (§9)

Push (§4), subscriptions (§5), affiliate (§6), and news (§2.4) can switch on after the
beta — they're all graceful-degradation until then.
