# Google Play Console — launch checklist (Wear The Mood)

App-specific checklist to get **Wear The Mood** (`com.fashionos.app`) onto the Play
Store. Tailored to what this app actually does: AI try-on from **selfies + body
data (biometric-sensitive)**, a digital wardrobe, social/UGC (posts, comments,
P2P giveaways), daily affiliate offers, and subscriptions. Legend: 🔵 founder
(account/UI/$, can't be automated) · 🟢 already done in the repo · ⚙️ a build/CLI step.

> **Inaccurate Data Safety / biometric declarations = rejection or removal.** Fill
> the sensitive-data sections honestly (sections 6–7). This app collects face/body
> imagery, so it gets extra scrutiny.

---

## 0. Locked app facts (do not change after first publish)
- **Package / applicationId:** `com.fashionos.app` 🟢 (permanent — can NEVER change post-publish, CLAUDE.md §6).
- **App name (Play listing, ≤30 chars):** `Wear The Mood` 🟢
- **Default version:** `1.0.0+1` (versionName `1.0.0`, versionCode `1`) — ✅ verified in the built APK; correct for the first submission, bump `version:` in `app/pubspec.yaml` every release. 🟢
- **SDK:** minSdk **24** · compileSdk **36** · **targetSdk 36** (Flutter 3.44.1) — ✅ **confirmed ≥ Google's API 35 minimum** (read from the built APK via `aapt`); no bump needed. 🟢

## 1. Account & one-time setup 🔵
- [ ] Google Play **developer account** ($25 one-time), identity-verified.
- [ ] **Merchant/payments profile** — confirm Play **payout to a Bangladesh bank** works (needed for paid subs).
- [ ] Create the app in Play Console: type **App**, **Free** (with in-app subscriptions), default language **English (US)**.

## 2. Store listing — text 🔵
- [ ] **App name:** Wear The Mood
- [ ] **Short description** (≤80 chars) — e.g. "See clothes on you before you buy. Your AI closet + daily stylist."
- [ ] **Full description** (≤4000 chars) — cover: AI try-on, digital wardrobe, daily stylist, community, free clothes/giveaways. Avoid medical/biometric over-claims.
- [ ] **App category:** Lifestyle (alt: Shopping). **Tags:** fashion, wardrobe, styling.
- [ ] **Contact email:** uprightseo24@gmail.com · **Website:** https://wearthemood.com · phone (optional).
- [ ] **Privacy Policy URL:** https://wearthemood.com/legal/privacy 🟢 (page drafted in `deploy/site/legal/privacy.html`).

## 3. Store listing — graphics 🔵 (exact specs)
- [ ] **App icon** — 512×512 PNG, 32-bit w/ alpha, ≤1 MB.
- [ ] **Feature graphic** — 1024×500 PNG/JPG (no alpha).
- [ ] **Phone screenshots** — 2–8, PNG/JPG, 16:9 or 9:16, each side 320–3840 px (recommend 1080×1920). Show: try-on reveal, closet grid, daily guide, community feed, paywall.
- [ ] (Optional) **7" + 10" tablet** screenshots (only if you list tablet support).
- [ ] (Optional) **Promo video** — a YouTube URL.

## 4. Content rating 🔵
- [ ] Complete the **IARC questionnaire**. Declare **user-generated content / social features** and **user-to-user communication** (posts, comments, giveaways) — this raises the rating and requires UGC moderation + reporting (🟢 built, CLAUDE.md §19).
- [ ] Expect a Teen/Mature-ish rating; keep it consistent with the **16+ minimum** (policy + target audience; no in-app age gate).

## 5. App content / declarations 🔵
- [ ] **Target audience & content:** set minimum age **16+** — stated in the privacy/acceptable-use policy + the Play target audience. **No in-app age gate** (founder decision: the app isn't age-restricted content). Declare biometric capture accurately in Data Safety; note the §10/§22 18+ recommendation was weighed and 16+ chosen.
- [ ] **Account deletion:** declare the in-app deletion path + the URL/flow. 🟢 In-app **account deletion + data export** are built (CLAUDE.md §10) — Play **requires** in-app deletion when accounts can be created.
- [ ] **Ads:** declare **No ads** (affiliate "shop the look" links are not Play "ads"; confirm).
- [ ] **News/COVID/financial/health:** none apply.
- [ ] **Government app:** no.

## 6. Data Safety form 🔵 — map honestly to what the app collects
Collected (all over HTTPS/TLS — Caddy + Supabase; **encrypted in transit = yes**):

| Data type | Collected | Purpose | Notes |
|---|---|---|---|
| **Photos** (selfies/avatar, wardrobe items, try-on results, posts) | Yes | App functionality, personalization | **Face/body imagery** — see §7. Raw try-on inputs auto-deleted (~72h, §10). |
| **Name** | Yes | Account, social profile | display name |
| **Email address** | Yes | Account management | auth |
| **User IDs** | Yes | Account | Supabase user id |
| **App interactions / in-app search / other actions** | Yes | Analytics | PostHog (§15) |
| **Crash logs / diagnostics** | Yes | App performance | Sentry (§14) |
| **User-generated content** (posts, comments, giveaway listings) | Yes | App functionality | moderated before public (§19) |
| **Purchase history** | If stored | Account / entitlement | subs via Play Billing + RevenueCat (§18) |
| **Device IDs** (FCM push token) | Yes | Push notifications | only after consent (§20) |

For each: declare **Data is encrypted in transit = Yes**, **Users can request deletion = Yes** (in-app), and whether **shared** (try-on inputs go to FASHN for processing — declare image processing by a third party; not "sold").
- [ ] Do **NOT** declare the service-role key / DB as collected user data.
- [x] **Photo/Video permissions declaration:** ✅ **not needed** — verified the built APK's merged manifest has **no `READ_MEDIA_IMAGES`/`READ_EXTERNAL_STORAGE`/`CAMERA`** (`image_picker` 1.x uses the Android **Photo Picker**). 🟢 Merged permissions are: `INTERNET`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, FCM (`c2dm.RECEIVE`/`FOREGROUND_SERVICE`/`RECEIVE_BOOT_COMPLETED`), `BILLING`, `USE_BIOMETRIC`/`USE_FINGERPRINT` (secure-storage keystore unlock — *not* fingerprint collection).

## 7. Privacy / legal / biometric 🔵🟢 (this app's sensitive bit)
> **16+, no in-app gate:** The app has **no in-app age gate** (founder decision — Wear The Mood is not age-restricted content). The **16+** minimum lives in the **public legal policy only**. ⚠️ A **final human/lawyer review of the 16+ wording across the privacy, acceptable-use, and terms pages is still required before Play Console submission.**
- [ ] **Host** the three legal pages at the exact URLs the app links to (🟢 drafted in `deploy/site/legal/`):
  - https://wearthemood.com/legal/privacy
  - https://wearthemood.com/legal/terms
  - https://wearthemood.com/legal/acceptable-use
- [ ] Fill any `{{PLACEHOLDERS}}` and have a lawyer review (biometric/face-body data → BIPA/GDPR special category).
- [ ] Privacy policy must clearly cover: **face/body data**, that **raw try-on inputs are deleted after processing (~72h)**, third-party processing (FASHN), and that data is never sold.
- [ ] **Explicit consent before any face/body capture** is enforced in-app (🟢 `consents`, §10).

## 8. Release — build & tracks ⚙️🔵
- [ ] ⚙️ Produce the **signed AAB** via the Codemagic `android-release` workflow (push a `v*` tag) — uses the `fashionos_upload` keystore + the `app_prod_config` env group (🟢 the hardened pre-build writes `env/prod.json`).
- [ ] 🔵 Enroll in **Play App Signing** (upload key = `fashionos_upload`).
- [ ] 🔵 **Closed testing first:** new personal accounts must run a closed test with **~12–20 testers for ~14 days** before production access — **recruit testers now** (§22). Use `TESTING_CHECKLIST.md` for the manual pass.
- [ ] 🔵 Internal testing track → closed → production. Write **release notes**.

## 9. Subscriptions / monetization 🔵 (can follow the free beta)
- [ ] Create the **subscription products** in Play Console (monthly + annual), then wire them as **RevenueCat offerings**; set RevenueCat `app_user_id` = Supabase user id (ACTIVATION §5).
- [ ] Set `REVENUECAT_API_KEY` + `REVENUECAT_WEBHOOK_AUTH` on the backend; point the RevenueCat webhook at `POST /v1/billing/webhook`.

## 10. Pre-launch / technical 🔵⚙️
- [ ] Review the **Pre-launch report** (Play runs your AAB on real devices) for crashes/policy flags.
- [ ] Confirm **HTTPS-only** networking (🟢 api.wearthemood.com is TLS via Caddy) — no cleartext.
- [ ] Confirm the live app points at **https://api.wearthemood.com** (🟢 via `env/prod.json` / the Codemagic step).

---

### Already in place (no action) 🟢
Backend live on `main`; in-app account deletion + data export; consent gating before biometric capture; UGC moderation + reporting; legal page drafts; the Codemagic release pipeline + prod dart-define step; package id + app name locked.

### Still founder-only 🔵
Play account + payout, all listing text/graphics, content rating questionnaire, Data Safety + biometric declarations, hosting the legal pages, recruiting closed testers, and the subscription products. None of these can be automated from the repo.
