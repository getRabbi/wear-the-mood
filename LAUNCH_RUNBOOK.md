# Launch runbook — Wear The Mood (`com.fashionos.app`)

The single, ordered path from "code is ready" to **live on Google Play**. Work it
top-to-bottom; each step lists its **owner**, **what it needs first (dep)**, and a
**done-when**. Detailed specs live in the linked docs — this is the sequence.

**Owners:** 🔵 founder (account / console / $ / design) · ⚙️ build step · 🟢 already done.
**Status legend:** ✅ done · ⏳ todo · ⛔ blocked (dep not met).

> Reference docs: `PLAY_STORE_CHECKLIST.md` (detail) · `STORE_LISTING.md` (copy) ·
> `PLAY_STORE_SCREENSHOTS.md` · `APP_ICON_BRIEF.md` · `FEATURE_GRAPHIC_BRIEF.md` ·
> `RELEASE_BUILD.md` (build) · `ACTIVATION.md` (backend/keys).

---

## Phase A — Already done 🟢 (no action)
- ✅ Backend live + TLS (`api.wearthemood.com`); app points at prod via `env/prod.json`.
- ✅ Live legal pages at **16+** (privacy / terms / acceptable-use) — hosted + verified.
- ✅ 16+ policy decision (no in-app gate); consent-before-capture, account deletion + export, UGC moderation — built.
- ✅ Repo checks: targetSdk **36**, no photo-permission declaration needed, version `1.0.0+1`.
- ✅ **Signed release AAB built + verified** (`app/build/app/outputs/bundle/release/app-release.aab`, `CN=Wear The Mood`).

---

## Phase B — Prerequisites (do first; unblock everything else)

### B1. 🔒 Back up the signing keystore — owner 🔵 · dep: none · **DO NOW**
- Back up `C:\Users\User\wearthemood-upload-keystore.jks` + `app/android/key.properties` (Drive + password manager).
- **Done when:** both stored in 2 safe places. *(Lose them → can't ever update the app.)*

### B2. Google Play account ready — owner 🔵 · dep: none
- ✅ Account purchased. Confirm **identity verification** complete + **payments/merchant profile** with a **Bangladesh payout** method (needed only for paid subs).
- **Done when:** Play Console shows the account active, no pending verification.

### B3. Final legal review — owner 🔵 · dep: none (parallel)
- Human/lawyer review of the **16+** wording across privacy / acceptable-use / terms (biometric → BIPA/GDPR special category).
- **Done when:** wording signed off (edit `legal/*.md` → re-run `deploy/build_legal.py` → redeploy if changed).

---

## Phase C — Build & first upload

### C1. Bump version (only for re-uploads) — owner ⚙️ · dep: none
- First upload uses `1.0.0+1` as-is. For any **rebuild**, bump `version:` in `app/pubspec.yaml` (versionCode must increase). See `RELEASE_BUILD.md`.

### C2. Signed AAB — owner ⚙️ · dep: B1
- ✅ Already built. To rebuild: `cd app && flutter build appbundle --release --dart-define-from-file=env/prod.json` → verify signer `CN=Wear The Mood`.
- **Done when:** a current `app-release.aab` exists, signed with the upload key.

### C3. Create the app + Internal testing release — owner 🔵 · dep: B2, C2
- Play Console → **Create app** (App · Free w/ subs · English US) → **Internal testing → Create release** → upload the AAB → accept **Play App Signing**.
- **Done when:** the AAB is processed on the Internal track with no blocking errors.

---

## Phase D — Store listing (can run parallel to C)

### D1. Listing text — owner 🔵 · dep: none
- Paste app name / short / full description / category / contact / privacy URL from `STORE_LISTING.md`.
- **Done when:** the "Main store listing" page validates.

### D2. Graphics — owner 🔵 (designer/generator) · dep: none
- **App icon** (512×512) from `APP_ICON_BRIEF.md`; **feature graphic** (1024×500) from `FEATURE_GRAPHIC_BRIEF.md`; **6–8 phone screenshots** from `PLAY_STORE_SCREENSHOTS.md` (demo data only).
- **Done when:** icon + feature graphic + ≥2 screenshots uploaded (≥4–8 recommended).

---

## Phase E — Declarations (the sensitive bit; do carefully)

### E1. Content rating (IARC) — owner 🔵 · dep: C3
- Complete the questionnaire; declare **UGC + user-to-user communication** (posts/comments/giveaways). Keep the rating consistent with **16+**.

### E2. Data Safety — owner 🔵 · dep: none
- Map honestly per `PLAY_STORE_CHECKLIST.md §6`: photos (face/body), name, email, user IDs, app interactions, crash logs, UGC, FCM token; **encrypted in transit = yes**, **deletable = yes**, **FASHN** = third-party image processing (not sold). Do NOT list the service-role key/DB.

### E3. App content — owner 🔵 · dep: none
- Target audience **16+**; declare **in-app account deletion** (built); **Ads = No**.
- **Done when (E1–E3):** all "App content" tasks show complete/green.

---

## Phase F — Test → Production

### F1. Closed testing — owner 🔵 · dep: C3, D1–D2, E1–E3
- New personal accounts must run a **closed test with ~12–20 testers for ~14 days** before production access. Recruit testers **now** (start during Phase C/D — it's the long pole). Use `TESTING_CHECKLIST.md` for the manual pass.
- **Done when:** ≥12 testers opted in and the 14-day window is satisfied with no critical bugs.

### F2. Pre-launch report — owner 🔵 · dep: C3
- Review Play's automated device-run report for crashes/policy flags; fix → rebuild (C1–C2) if needed.

### F3. Production release — owner 🔵 · dep: F1, F2, D, E
- Promote to Production; write release notes; submit for review.
- **Done when:** app is live (or in review) on the Production track.

---

## Phase G — Post-launch (can follow the free launch)
- **Subscriptions:** create products in Play Console → wire RevenueCat offerings; set backend `REVENUECAT_API_KEY` + webhook (`ACTIVATION.md §5`).
- **Day-1 keys (optional):** OpenAI stylist, Firebase push, Google sign-in — gate features, not blockers.
- **iOS:** later, via borrowed Mac + Codemagic (`codemagic.yaml` `ios-compile-check` already runs monthly).

---

## Critical path (the long pole)
**B2 → C3 → F1 (14-day closed test) → F3.** Everything else (D, E) runs in parallel
but must finish before **F3**. Start **F1 tester recruiting immediately** — it gates
production by ~2 weeks regardless of how fast the rest goes.
