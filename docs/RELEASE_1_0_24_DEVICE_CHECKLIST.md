# Real-device verification — 1.0.24+29

Everything below runs against **production** (`api.wearthemood.com`, commit
`e762bee`) with the release flags already ON:
`wardrobe_require_metadata`, `wardrobe_require_known_category`,
`tryon_strict_categories` = true; `feature_credit_economics_v2`,
`feature_render_gate_v2` = false; free lifetime renders = 3.

Record the numbers as you go. A step with no recorded number is a step that was
not verified.

---

## 0. Install and identity

- [ ] Install from **Google Play Internal Testing**, not a sideload. The
      Play-delivered build is signed by the Play App Signing key, and Google
      Sign-In behaves differently under it (see `docs/ANDROID_SIGNING_KEYS.md`).
- [ ] `adb shell dumpsys package com.fashionos.app | grep -E "versionName|versionCode"`
      → expect `1.0.24` / `29`.
- [ ] `installerPackageName` → `com.android.vending` (proves it came from Play).

## 1. Auth

- [ ] Google Sign-In on a **fresh** install. ⚠️ It can succeed once from cache —
      sign OUT and back in to actually test it.
- [ ] Email sign-up + sign-in.
- [ ] Onboarding completes.

## 2. Consent v2 — all four cases

Consent is account-level and server-side. Reinstalling does not reset it.

### Case 1 — fresh account, Allow
- [ ] New account, no prior consent. Start an AI render (MoodMirror → body photo
      → garment → AI Couture → Generate).
- [ ] Disclosure appears **before** anything is sent. It names FASHN and OpenAI.
- [ ] Tap **Allow** → render proceeds.
- [ ] Credits before: ____  after: ____ → **difference must be exactly 1**.
- [ ] Generate again → **no sheet**.

### Case 2 — fresh account, Not Now
- [ ] Second new account. Start a render, tap **Not Now**.
- [ ] Credits before: ____  after: ____ → **must be identical**.
- [ ] No render appears, no job in history.
- [ ] Tap Generate again → sheet reappears.

### Case 3 — an account holding v1
- [ ] Production currently has **1 account on consent v1**. Sign in as it.
- [ ] First AI render shows the v2 sheet **once**.
- [ ] Allow → proceeds. Next render → no sheet.

### Case 4 — persistence and revocation
- [ ] With consent granted: force-stop, relaunch → no sheet.
- [ ] Sign out, sign back in → no sheet.
- [ ] **Uninstall and reinstall** → still no sheet (it is account state, not device state).
- [ ] Profile → ⋯ → Settings → Privacy & data → AI Photo Processing →
      **Withdraw permission** → status reads NOT ALLOWED.
- [ ] Next AI render asks again. Decline → credits unchanged.

## 3. Categories

- [ ] Add a garment: photo → background removal → **cutout preview appears** →
      only then are name and category asked.
- [ ] **No category is preselected.**
- [ ] Save is disabled until both a name and a category exist.
- [ ] The line above Save reads `Try-on type: <category>`.
- [ ] All **12** categories are selectable: Tops, Bottoms, Dresses, Outerwear,
      Shoes, Bags, Hijab, Hats, Eyewear, Jewelry, Belts, Other.
- [ ] Each tile shows examples (e.g. Bottoms → "Pants, jeans, skirt, shorts").
- [ ] Belts and Other show "Not worn in try-ons yet".
- [ ] Save a **Hijab** and a **Jewelry** (watch) item — the two the old build
      could not express. Both appear under the **Accessories** filter.
- [ ] Filters: each of the 7 chips shows the right pieces.
- [ ] Add a SECOND garment immediately → the form is blank, nothing inherited.
- [ ] Open a saved piece → tap the category chip → Edit → change it → the chip updates.

## 4. Legacy repair

Production holds **65 items with a blank category and 7 filed as "accessories"**.

- [ ] Open one of them → **Try On** → the resolver sheet appears with the real
      garment thumbnail.
- [ ] Pick a category → **Save & Try On** → the try-on continues **by itself**.
- [ ] Credits before: ____  after: ____ → **exactly 1**.
- [ ] Repeat, but **dismiss** the resolver → no job, credits unchanged.
- [ ] Closet shows a dismissible "Review N items" banner.

## 5. Credits — one per render, three lifetime free

Use a brand-new free account. Record every number.

| # | Action | Credits before | after | expected |
|---|---|---|---|---|
| 1 | 2D try-on | | | 0 |
| 2 | AI Couture #1 | | | −1 |
| 3 | AI Couture #2 | | | −1 |
| 4 | AI Couture #3 | | | −1 |
| 5 | AI Couture #4 | | | **blocked, 0** |
| 6 | Free mood planning / saved looks after #5 | | | still usable |

- [ ] On a Pro Max account: **HD render costs 1**, not 4.
- [ ] Multi-garment full look costs **1**.
- [ ] AI Enhance costs **1**.
- [ ] Force a failure (airplane mode mid-render) → the credit comes **back**, net 0.
- [ ] Double-tap Generate → **one** job, **one** credit.
- [ ] Kill the app mid-render, reopen → the result is recoverable, still one charge.

## 6. Duplicates

- [ ] Add a garment, and while Save is in flight turn airplane mode on and off.
- [ ] Retry Save → the closet gains **one** item, not two.
- [ ] Rapid double-tap Save → **one** item.

## 7. Stability

- [ ] `adb logcat -c` then exercise the app; `adb logcat -d | grep -iE "FATAL|AndroidRuntime"`
      → **empty**.
- [ ] Discover, Closet, Mirror, Stylist, Profile all navigate without a crash.
- [ ] Paywall opens after the free allowance is spent.

---

## Known environment notes

- MIUI blocks synthetic touch injection into the system file picker. Selecting a
  photo by hand (or via DPAD) is expected and acceptable.
- FASHN balance at the start of this run: **99 credits**. A standard render costs
  FASHN 1; AI Enhance costs 2. Checking the balance before and after is a second,
  independent way to prove exactly one provider call happened.
