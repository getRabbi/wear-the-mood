# Final mobile build session — status

**Session of 2026-08-12.** Release candidate is `release/1.0.21` (pushed;
`main` deliberately untouched). Everything below is recorded from commands that
actually ran in this session — where a thing was *not* verified, it says so
rather than being ticked.

## Where things stand

| | |
|---|---|
| Release candidate | `release/1.0.21` @ `21f402a`, pushed |
| App version | `1.0.21+25` (was `1.0.20+24`) |
| Production API | `wtm-api-prod` v39, `6ac1bbe` — consent enforcement live, **not redeployed this session** |
| Databases | `0066` applied to dev + prod; `feature_flags` rows changed (below) |
| Legal site | **republished** this session — assetlinks fix live, ops-console proxy verified intact |
| Admin console | working; re-validated (lint + 75 tests + prod build) |
| Discover | **live in production** — discover + stories + shopping all on, client default changed |

---

## What changed in the release candidate

`deploy/timing-instrumentation` already contained **all** of `main` and **all**
of `fix/production-eight-defects`. The one commit that looked missing,
`f41e9f3`, is a cherry-pick duplicate of `dc36139` — identical `git patch-id`
(`e7b6322…`). Nothing needed re-integrating and nothing was duplicated.

Five commits on top:

| Commit | What |
|---|---|
| `e69b33c` | merge of `cdee5af` — iOS Settings deep link for the denied-notification CTA (checklist item C) |
| `efdec7b` | version bump `1.0.21+25` |
| `555383a` | **`assetlinks.json` Play App Signing fix** (B2 — see below) |
| `71b1ca4` | **Discover is the default surface**, not a staged rollout |
| `21f402a` | pin `wtm_shell_test` to a definitive flags answer |

Feature branches confirmed fully merged (`0 commits ahead` each):
`feat/awin-connector`, `feat/product-news-automation`,
`fix/enhance-quality-giveaway-state-notifications`.

---

## Discover replaces Social

Discover was never missing from the build — it was gated off by a server flag.

**Production `public.feature_flags`:**

| Key | Before | After |
|---|---|---|
| `feature_discover` | false | **true** |
| `feature_discover_stories` | false | **true** |
| `feature_shopping` | false | **true** |

Rollback:
```sql
update public.feature_flags set enabled=false
 where key in ('feature_discover','feature_discover_stories','feature_shopping');
```

> **`feature_shopping` is not just the catalog.** In `DiscoverPage.compose` the
> **Giveaway campaign card and the Newsroom card sit inside
> `if (shoppingEnabled)`**, together with the product rows and Complete Your
> Look. Shipped with it off, Discover was the story rail and the mood pulse and
> nothing else — which reads as "giveaways and newsroom are broken" when it is
> exactly what that one flag is documented to do. Verified on device after
> flipping it: Picked for You, View Giveaway, the Newsroom read and New for your
> mood all render, against 5 products, 4 live giveaways and 2600 news items.

`shopping` is deliberately **not** added to the client's
`onUntilBackendSaysOtherwise`. `discover` changes the tab's identity with no
network dependency, so the flash mattered; `shopping` gates content that needs a
fetch anyway, so an optimistic default would only draw empty skeletons sooner.

**Client** (`71b1ca4`): `featureEnabledProvider` now separates "the backend has
not answered" (loading/error) from "the backend answered and omitted this key".
Only the first consults a default, and only `discover` + `discoverStories`
default ON. Without this every cold launch drew tab 1 as Social and swapped once
the flags request landed — and fell back to Social whenever that request failed.

**The kill-switch is intact and tested.** A definitive backend answer wins in
both directions, so setting `feature_discover=false` still pulls Discover from
every client on the next refresh (DISCOVER §30).

---

## A. Device evidence

### A1. Android — CLEARED

Device: **Xiaomi M2007J20CG (surya), Android 11 / API 30**, the same handset as
the existing ledger entry. Fingerprint unchanged at **`ce512df42aa97fc6`** —
verified with `--print-fingerprint` after every commit, since no native Kotlin
source was touched.

Four real Add Garment cutouts on the **release** build (fresh install after
uninstall, so first-run engine setup is covered too), 0 crashes, 0 failures:

| # | Subject | total | inference | coverage |
|---|---|---|---|---|
| 1 | floral dress on patterned background | 2076 ms | 739 ms | 0.41 |
| 2 | floral dress | 2312 ms | 1008 ms | 0.41 |
| 3 | floral dress | 1907 ms | 620 ms | 0.41 |
| 4 | **tortoiseshell eyeglasses** | 1685 ms | 552 ms | **0.02** |

`init_ms=0` on all four, against 517 ms in the 1.0.19+22 session — the
urgent-preparation path warms the engine before the first photo, which is the
warm-up defect fix measured rather than asserted. All four persisted through
Save to Closet and render transparent in the closet grid.

With the one run already on file that is **5 runs across 2 sessions**, and

```
python scripts/verify_local_cutout_release.py --target android-production \
  --artifact app/build/app/outputs/bundle/release/app-release.aab
```

now reports **All 20 invariants hold** (exit 0) against the shipping bundle.

### A2. iOS — STILL NOT RUN

Fingerprint **`2cb72faffd771f44`**, unchanged. Apple Vision has still never
produced a cutout on physical hardware. The TestFlight build was produced with
`PRE_DEVICE_VALIDATION=true`, which is the documented escape from the
chicken-and-egg (the IPA has to exist before anyone can run the matrix). **This
does not clear A2** — it defers it. A2 remains a release blocker for the App
Store, and is untouched by anything done in this session.

---

## B. Verify

### B1. Google sign-in on a Play-delivered build — NOT TESTED
Untestable this session: it requires a build delivered *by Play*, tested *after
an explicit logout*. Sideloaded builds cannot prove it.

### B2. `assetlinks.json` — DEFECT FOUND, FIXED AND **DEPLOYED**

The file listed exactly one fingerprint:
`27:CC:B9:D8:…:BD:73:D0`. Verified with `keytool` against
`wearthemood-upload-keystore.jks` that this is the **upload key** (its SHA-1
`89:C6:D1:2E:…` matches `ANDROID_SIGNING_KEYS.md` exactly).

Google re-signs every Play release with the **Play App Signing** certificate,
whose SHA-256 is `0F:EB:F2:B7:…:9F:2C:EA` — a value that appeared only in docs
and **never in `assetlinks.json`**. So App Links verification succeeded for
sideloaded QA builds and failed for every production install. Referral deep
links depend on it.

`555383a` lists **both** fingerprints, and it is now **live**. Published to the
Cloudflare Pages project `wtm-site` (which serves wearthemood.com) from a staged
tree of `deploy/site` **plus `deploy/functions`** — the functions directory lives
outside `deploy/site`, so deploying that folder alone would have dropped the
ops-console proxy.

Verified after publishing:

| | |
|---|---|
| `/.well-known/assetlinks.json` | both fingerprints, Play App Signing first |
| `/mood-ops-console-7x9` | HTTP 307 — proxy intact |
| `/legal/privacy` | HTTP 200 |
| `/` | HTTP 200 |

Rollback: redeploy `3eab1d58-f8e0-45de-a204-6e92e34d371b` (the production
deployment immediately before this one, 2026-08-12T05:54:35Z).

### B3. Lawyer review of the 13+ wording — NOT DONE (unchanged, external)

---

## Validation run this session

Every command below was executed; counts are from its own output.

| Check | Command | Result |
|---|---|---|
| Flutter analyze | `flutter analyze` | **No issues found** (347s) |
| Dart format | `dart format --set-exit-if-changed lib test` | **632 files, 0 changed** |
| Flutter tests | `flutter test` | **1521 passed** |
| Backend | `backend\.venv\Scripts\python.exe -m pytest backend/app/tests -q` | **1307 passed, 44 skipped** |
| Kotlin native | `./gradlew :app:testDebugUnitTest --tests "com.fashionos.app.background.*"` | **157 tests, 0 failures, 0 skipped** |
| admin-web lint | `npm run lint` | No ESLint warnings or errors |
| admin-web tests | `npm test` | **75 passed / 11 files** |
| admin-web build | `npm run build` | Succeeded, all routes |
| Local-cutout (android) | `verify_local_cutout_release.py --target android-production` | all structural gates pass; device evidence outstanding |
| Local-cutout (ios) | `--target ios-production` | all structural gates pass; device evidence outstanding |

> The Kotlin "BUILD SUCCESSFUL" was **not** taken at face value — the JUnit XML
> under `app/build/app/test-results/` was parsed to confirm 157 tests actually
> executed, because a suite that runs nothing also exits zero.

**Not run locally:** `gitleaks` (not installed; CI-only), and the `build_runner`
codegen check (deferred to avoid corrupting an in-flight APK build).

---

## Apple 5.1.1(i) — verified in code

- **Ordering is correct.** `backend/app/routers/v1/tryon.py`: consent at **299**,
  URL freshening at **307**, OpenAI moderation at **321**, credit reservation at
  **331**. Nothing has left the server and nothing is charged at line 299 — which
  matters because moderation is *itself* a third-party transmission of the same
  photo.
- **Client gate is fail-closed** (`ai_consent_gate.dart`): unknown state or an
  unreachable API asks rather than assumes; a failed grant-write returns false
  instead of proceeding.
- **Both AI entry points gate** — `tryon_screen.dart:240` and
  `wtm_mirror_step3.dart:258` — through one `ensureAiConsent`, classified by a
  typed `AiInputPrivacy` so a new AI surface cannot be written without naming
  its classification.
- **Disclosure names the real processors** and matches `legal/privacy.md`,
  including the order the code actually uses: OpenAI safety check first, then
  FASHN.ai (FASHN LTD).
- Account **deletion** (`account.py:129`) and **export** (`account.py:103`) present.

### Verified ON THE DEVICE — the first time this has ever run on hardware

Release build `1.0.21+25`, fresh install, personal body photo (`own_photo`):

- **The sheet appears on Generate, before anything is transmitted.** It names
  **FASHN.ai (operated by FASHN LTD)** and **OpenAI**, says the safety check
  happens *first*, disclaims facial recognition and biometric profiling, offers
  a decline, and links the Privacy Policy.
- **Grant is recorded server-side**, versioned and provider-scoped:
  `user_privacy_consents … consent_version=1,
  provider_scope='openai_moderation,fashn', granted_at=2026-08-12 08:50:23Z`.
- **Settings → Privacy & data** shows **ALLOWED**, matching the database, with
  Review disclosure / Withdraw permission, and states correctly that 2D and
  studio-model try-on never send the photo.
- **Withdraw works end to end** — `revoked_at=2026-08-12 09:10:44Z`.
- **Nothing was charged and no job was created** across the whole session:
  `tryon_jobs` in the last 30 min = **0**, `credit_transactions` in the last
  40 min = **0**, balance steady at 174.
- **A render with no body photo refuses to start** and routes to the body
  picker instead — the `personUrl == null` guard, so a paid job can never
  silently render on a stranger.

**Two consent sub-cases still not device-tested:** the explicit **Not Now**
decline (the tap landed on Allow, and the grant is in the database to prove it),
and **second render shows no sheet**. Consent is currently *revoked* on this
account, so the next personal-photo render should ask again — which is the
"after withdrawing, it asks again" case ready to be observed.

## Eight defect fixes — verified present

All six commits are in the RC. Spot-checked in depth:

- **Giveaway delete is a hard delete** — `giveaways.py:616` is a real `DELETE`,
  and the cascade is at schema level: giveaway → claims (`0020:35`) → pickup chat
  (`0037:38`) → messages (`0037:77`), all `on delete cascade`. Permanent, for
  everyone, no soft-delete. `de0cd95` (Delete on the screen production actually
  renders) is in the RC, so the known "owners see no delete" gap is fixed.
- **Notification icon** — `ic_stat_wtm` present at all five densities and wired
  via `default_notification_icon` in `AndroidManifest.xml:93`.

## Credit rules and provider settings — unchanged

HD = 4 credits (Pro Max only), standard = 1 (`tryon.py:271-278`). FASHN default
`mode: str = "quality"`. Person image still inlined as base64
(`tryon_worker.py:98-117`). None of these were touched.

---

## Try-On timing (Phase 7A measurement) — DONE

Three renders, correlated across client / Heroku / Azure.

| | Render 1 (cold) | Render 2 | Render 3 |
|---|---|---|---|
| Submit total | **8966 ms** | 3112 ms | 3767 ms |
| ├ moderate_garments | **7667 ms** (2) | 2069 ms (2) | 2712 ms (2) |
| └ enqueue | 989 ms | 776 ms | 772 ms |
| Worker startup | **1.2 s** | 1.2 s | 1.3 s |
| Worker total | 70627 ms | 61392 ms | 64170 ms |
| └ FASHN (2 calls) | **63011 ms** | 54807 ms | 57217 ms |
| User-perceived | ~52 s (partial) | **97.4 s** | **99.8 s** |

**Conclusions, and they change the Phase 7B plan:**

1. **There is no cold-start problem.** `startup=1.2s` on the genuinely cold run.
   The hypothesis this instrumentation was built to test is disproved.
2. **FASHN is 89% of worker time**, serial across the two garments. Out of
   scope — `quality` is retained by instruction.
3. **Moderation is 66–86% of our own submit latency**, and is serial. Concurrent
   moderation remains the one large controllable block — but it is only ~2–4% of
   the ~97 s the user actually waits.
4. **Instant navigation after Generate is not worth doing.** `body_resolved` is
   **0–4 ms** and `ui_visible` **6–28 ms**. The gap it targets does not exist.
5. `first_poll` is a consistent ~2.4 s of dead time — real, small.

**Phase 7B was deliberately NOT applied.** Every remaining candidate is either a
production API deploy for a ~2–4% end-to-end gain, or a change to the paid
job-polling path, in the middle of a release. Evidence is recorded here so the
decision can be revisited on its merits.

### Instrumentation defect found

`wtm_mirror_step3.dart:198` builds the trace from a fresh `uuidV4()`, not from
the idempotency key the repository actually sends, so the client and server
tokens disagree on the primary path — only the resume path matched. The three
runs above were correlated **by timestamp** instead. Debug-only, no user impact,
but the correlation token does not correlate. Not fixed.

---

## Still outstanding

1. **A2 — iOS device matrix.** Never run. Release blocker for the App Store.
2. **Two consent sub-cases** — explicit *Not Now*, and *second render shows no
   sheet*. The gate itself, the grant, the Settings control and withdrawal are
   all now device-verified (above).
3. ~~**B2 deploy.**~~ DONE — published and verified live.  Previously: inert until
   `deploy/site` is published.
4. **B1** — Google sign-in after logout on a Play-delivered build.
5. **B3** — lawyer review of the 13+ wording.
6. **Android 13+ notification permission** cannot be exercised — the test device
   is API 30.
7. **`TARGETED_DEVICE_FAMILY = 1`** — the app is iPhone-only; iPad runs it in
   scaled compatibility mode. Not a regression, but it bounds what iPad QA means.
8. Stale, inert feature-gate values still sit in the Codemagic `app_prod_config`
   group (e.g. `LOCAL_BG_IOS_ENABLED=false`). `render_app_env.py` ignores them —
   gates come only from the committed policy — but they mislead a human reader.
