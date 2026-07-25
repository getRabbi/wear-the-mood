# Phase 6 — manual live production test checklist

**Build under test**

| | |
|---|---|
| APK | `E:/dopplefit/app/build/app/outputs/flutter-apk/app-release.apk` |
| SHA-256 | `d740a1f3ba6b537675a6abaf1db7bbfbaa31e3b23bc1ee8b6a72327114fd0ce6` |
| Package | `com.fashionos.app` |
| Version | **1.0.9 (versionCode 10)** |
| Signed with | upload key — `CN=Wear The Mood`, SHA-256 `27ccb9d8…` |
| Git commit | `a83d6c0` — branch `migration/heroku-azure`, tree clean |
| API | `https://api.wearthemood.com` → **Heroku** |
| Supabase | `ghzabbceoaoertatkjyg` (**US, authoritative**) |
| Device | Xiaomi M2007J20CG, Android 11, arm64-v8a |
| Installed | 2026-07-21 00:12:18Z · launched, `MainActivity` resumed, **0 crashes** |

**Read before starting**

- The previous install was a **debug** build and was uninstalled (signature mismatch), so this is a
  **fresh install with no session** — you will need to log in.
- **Google Sign-In is inactive** in this build (`GOOGLE_WEB_CLIENT_ID` is empty). Use **email/password**.
- Server data (profile, closet, outfits, credits, community) lives in Supabase and was **not** affected
  by the reinstall.
- **D and E involve real money.** Run **exactly one** paid AI try-on. Do not repeat it.
- Background removal is expected to take up to ~3 minutes on a cold worker. That is **normal**, not a bug.

---

## A. Launch and authentication

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| A1 | Cold launch (force-stop, reopen) — no crash, no blank screen | | |
| A2 | Log in with email/password | | |
| A3 | Log out, then log in again | | |
| A4 | Session survives a full app restart (kill from recents, reopen — still logged in) | | |
| A5 | Auth error handling: try a deliberately wrong password — clear message, no crash | | |
| A6 | Password reset email sends (only if safe to trigger) | | |

## B. Existing production data

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| B1 | Profile loads (name, avatar, bio) | | |
| B2 | Closet / wardrobe items load | | |
| B3 | Item images display (no broken/placeholder images) | | |
| B4 | Outfits / saved looks load | | |
| B5 | Community / followers data loads | | |
| B6 | **No missing items and no duplicates** vs what you expect | | |
| B7 | Record item count seen: ______ | | |

## C. Upload and background removal  ⏱ record times

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| C1 | Upload one real clothing photo | | |
| C2 | Upload appears in the closet | | |
| C3 | Background removal starts | | |
| C4 | **Start time** (hh:mm:ss) | | |
| C5 | **"Still preparing…" appears** at ~45 s — time: ______ | | |
| C6 | **Completion time** (hh:mm:ss) → **total elapsed: ______** | | |
| C7 | Result correct (background actually removed, item looks right) | | |
| C8 | **Does NOT wrongly fail at 45 s** | | |
| C9 | **Does NOT wrongly fail at 90 s** | | |
| C10 | Leave the screen mid-processing and come back — still processing/completes | | |
| C11 | Fully close and reopen the app — status refreshes correctly | | |
| C12 | Completed within ~3 min (if longer, note exact time — do not assume failure) | | |

## D. AI try-on — **ONE paid run only**

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| D1 | Submit **one** AI try-on | | |
| D2 | Shows submitted/queued state | | |
| D3 | Shows processing state | | |
| D4 | Completes with a result image | | |
| D5 | Result image renders correctly | | |
| D6 | Result is saved and still there after leaving and returning | | |
| D7 | **Start / finish time → elapsed: ______** | | |

## E. Credits and failure behaviour

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| E1 | **Credits BEFORE the AI request: ______** | | |
| E2 | **Credits AFTER: ______** | | |
| E3 | Exactly **one** deduction (no double charge) | | |
| E4 | Balance still correct after app restart | | |
| E5 | If a failure occurs naturally: refund happens exactly once (do not force one at cost) | | |
| E6 | Retry does not create duplicate jobs or duplicate results | | |

## F. Community and profile

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| F1 | Feed loads | | |
| F2 | Open another user's profile | | |
| F3 | Create or view a post (text / image / poll) where safe | | |
| F4 | Your profile picture and bio load | | |
| F5 | Followers / following screens work | | |

## G. Notifications

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| G1 | Notification preferences screen opens | | |
| G2 | OS permission state displays correctly | | |
| G3 | "Open Settings" opens Android settings | | |
| G4 | Toggle a category and confirm it persists after reopening | | |
| G5 | If a notification arrives, tapping it opens the correct screen | | |
| G6 | Push token registers **after login** (pre-login 401 is expected — see notes) | | |

## H. Website and deep links

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| H1 | `https://wearthemood.com` loads | | |
| H2 | `/legal/privacy` loads | | |
| H3 | `/legal/terms` loads | | |
| H4 | `/legal/acceptable-use` loads | | |
| H5 | `/delete-account` loads | | |
| H6 | Open a `/r/<code>` referral link — reaches the expected app/site flow | | |
| H7 | Tapping a `wearthemood.com` link opens the **app** (App Links), if supported by this build | | |

## I. Stability

| # | Test | PASS/FAIL | Notes |
|---|---|---|---|
| I1 | Switch rapidly between main tabs/screens — no crash | | |
| I2 | Background the app, resume — state intact, no forced logout | | |
| I3 | Works on Wi-Fi | | |
| I4 | Works on mobile data | | |
| I5 | No endless spinner, blank page, or unexpected logout anywhere | | |

---

## J. Final evidence to send back

1. **PASS/FAIL for every numbered item above.**
2. **Background-removal timing** — C4, C5, C6 (start, "still preparing", completion).
3. **AI try-on timing** — D7.
4. **Credit balance before and after** — E1, E2.
5. **Screenshots of any failure.**
6. **Exact error message and the screen it appeared on.**

> Phase 6 stays open until this comes back. Rollback to DigitalOcean remains one DNS call away
> for both `api.wearthemood.com` and `wearthemood.com` (see `PHASE_6_REPORT.md` §7).
