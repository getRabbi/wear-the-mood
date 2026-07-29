# Local-first background removal — validation & release-candidate report

**Branch** `feat/local-first-background-removal`
**Validated commit** `958a56f`
**Dates** 2026-07-28 (automated) · 2026-07-29 (Android device)
**Verdict** **Android local background removal WORKS on device and is safe to
activate behind its gates after a rollout decision. iOS is still entirely
unvalidated.** All five gates remain OFF.

Updated 2026-07-29 after three device-driven fixes; the earlier "no device has ever
executed local inference" verdict no longer applies to Android. It still applies to
iOS in full.

This report deliberately separates four things: **passed**, **real-device**,
**unavailable**, and **risks**. Nothing unexecuted is described as passing.

---

## 0. Android device outcome (2026-07-29)

Three bugs were found on hardware that no automated suite had caught, and each is
fixed and covered by tests.

| # | Bug | Fix | Commit |
|---|---|---|---|
| 1 | The mask PNG carried the confidence in R/G/B with `alpha = 0xFF`. The server reduces an alpha-bearing mask via `getchannel("A")`, so it measured coverage 1.0 and rejected **every** ingest with 422. | Confidence goes in **alpha**, mirrored into R/G/B, unpremultiplied. | `b8129b3` |
| 2 | `SoftMask.toAlpha` coerced NaN to 0 and clamped 3.4e38 to 1, turning a corrupt SDK buffer into a saved cutout. | Validate **first**; reject rather than coerce. | `582b44e` |
| 3 | ML Kit's full `foregroundConfidenceMask` is corrupt at the source: **15–96% NaN/out-of-range**, varying run to run. Copying it inside the success callback on a direct executor did **not** help, so the buffer-lifetime hypothesis is **disproved**. | Stop requesting it. Reconstruct from **per-subject confidence masks**, which measured zero NaN. | `958a56f` |

### The Android implementation, as it now stands

* **Per-subject confidence masks are authoritative.** `enableForegroundConfidenceMask()`
  is not called and that buffer is never read.
* Each subject mask is placed at its own **validated** bounds; overlapping pixels take
  the **maximum** confidence. Nothing is resized and nothing is thresholded.
* **Safety range `[-0.25, 1.25]`**, then clamped to `[0,1]`. This is deliberately a
  separate, wider policy from the `1e-3` drift check: the per-subject mask is raw
  model output and is *not* normalised — it measured `min=-0.183 max=1.180` with ~24%
  of values slightly above 1.
* **Zero tolerance** on the rest: any NaN, any infinity, any value outside the safety
  range, a mask length that disagrees with its bounds, bounds outside the source, no
  reported subject, or coverage outside `0.005..0.995` → a **typed failure**, which
  degrades to the existing Azure BiRefNet path. Validation completes before a single
  pixel is written, so a bad mask cannot partially contaminate the output.

### Measured on a POCO X3 NFC (Android 11, arm64, Play services 26.26.34)

| Metric | Result |
|---|---|
| Consecutive runs | **31** |
| SIGSEGV | **0** (previously 1 in 8, with the foreground mask enabled) |
| Typed rejections | **0** |
| `POST /v1/wardrobe/local-cutout` | succeeded; items born **`cutout_status=done`, `attempt_count=0`** |
| Legacy `POST /v1/wardrobe` | **0** — no cloud create on a valid local result |
| Azure BiRefNet jobs | **0** on valid local results |
| Distinct source images visually checked | **9** |
| Total latency | min 1804 / **median ~2.6 s** / max 2703 ms |
| Inference | 639–797 ms |
| Same-image determinism | coverage **0.41 on 14/14 runs**; 116 ms spread |

Visual quality was confirmed by pulling the stored mask and cutout from R2 and
compositing over white. A patterned kurta, **black trousers** (foreground brightness
28.8/255) and a pair of **eyeglasses** (thin frame arms preserved, lenses correctly
transparent) all came out clean. Edge complexity 5.8–25.9 transitions/row with
0.5–1.8% soft-edge pixels — real soft alpha, versus 213–305 transitions/row when the
mask was corrupt.

> **A native crash still bypasses the typed fallback.** A `SIGSEGV` inside the SDK's
> own `.so` kills the process; no Kotlin or Dart handler can catch it. Zero in 31 runs
> is encouraging and dropping the foreground mask plausibly removed the crashing path,
> but it is **not** proof of absence, and this document does not claim every possible
> failure is catchable.

---

## 1. Passed — automated

Every command below was executed on 2026-07-28 and its output observed.

### 1.1 Flutter

| Command | Result |
|---|---|
| `flutter analyze` | **No issues found** (149.9 s) |
| `flutter test` (full suite) | **810 passed, 0 failed** |

Local-first BG contributes **175 of those 810**:

| Suite | Tests |
|---|---|
| `test/features/local_cutout/local_cutout_orchestrator_test.dart` | 34 |
| `test/features/local_cutout/local_cutout_models_test.dart` | 28 |
| `test/features/local_cutout/local_cutout_method_channel_test.dart` | 22 |
| `test/features/local_cutout/local_cutout_analytics_test.dart` | 21 |
| `test/features/local_cutout/local_cutout_quality_policy_test.dart` | 18 |
| `test/ui/wtm_improve_cutout_test.dart` | 17 |
| `test/ui/wtm_add_garment_local_test.dart` | 15 |
| `test/data/wardrobe_local_cutout_repository_test.dart` | 11 |
| `test/features/local_cutout/local_cutout_cache_test.dart` | 9 |

### 1.2 Backend

| Command | Result |
|---|---|
| `python -m pytest -q` | **785 passed, 1 skipped, 0 failed** (178 s) |
| `python -m ruff check app` | All checks passed |
| `python -m ruff format --check app` | 246 files already formatted |

Local-first BG contributes **83**: `test_local_cutout.py` 52, `test_improve_cutout.py`
15, `test_mask_ingest.py` 13, `test_local_cutout_gate.py` 3.

Two things had to be fixed to get a clean run — both recorded honestly:

* **`anthropic` was not installed in the local venv**, failing 8 unrelated
  stylist/news/packing LLM-routing tests with `ModuleNotFoundError`. It is a
  *declared* dependency (`requirements.txt:14`, `anthropic>=0.40.0`), so this was a
  local environment gap, never a code regression, and production images were never
  affected. Installed locally; those 8 now pass.
* **One assertion of mine was wrong.**
  `test_a_blank_object_key_is_rejected_and_creates_nothing` expected 422. A blank
  string is a valid `str`, so it reaches the handler and gets the same **404** as
  someone else's key — deliberate, so the endpoint cannot distinguish "malformed"
  from "not yours" (§11). The test now asserts 404, and a **new** test covers the
  genuinely-absent field (422). Production behaviour was correct all along; only the
  test was wrong.

### 1.3 Android

| Command | Result |
|---|---|
| `gradlew :app:cleanTestDebugUnitTest :app:testDebugUnitTest` | **144 passed, 0 failures, 0 errors** (2026-07-29; was 83 before the device fixes) |
| `flutter build apk --debug --dart-define-from-file=env/prod.json` | **BUILD SUCCESSFUL** |

`cleanTest` was required: a plain `testDebugUnitTest` reported `UP-TO-DATE` from the
Phase 3 cache, which is not an execution. Per-suite, from the JUnit XML:

| Suite | Tests |
|---|---|
| `GoogleSubjectSegmenterEngineTest` | 35 |
| `SoftMaskTest` | 24 |
| `LocalCutoutCacheStoreTest` | 16 |
| `LocalCutoutAsyncTest` | 12 — callback-time deep copy, lifetime isolation, exactly-once |
| `LocalCutoutIntegrityTest` | 11 — corrupt-buffer rejection, reconstruction, no leftover scratch |
| `ConfidenceValidationTest` | 11 — NaN/infinity/out-of-range, tolerated drift |
| `SubjectMaskCombineTest` | 17 — placement, overlap max, bounds, safety range |
| `SingleOperationGuardTest` | 10 |
| `MaskPixelPackingTest` | 8 — the mask channel contract |

### 1.4 iOS

| Item | Result |
|---|---|
| Codemagic `ios-compile-check`, build `6a685542d621c72943a315bd` | **finished — all 9 steps success** |
| Branch / commit actually built | `feat/local-first-background-removal` @ `8797269` |

All nine steps green, including *Analyze + test* (analyze + full Flutter suite on
macOS) and *Build iOS (no codesign)*. This compiles all six
`app/ios/Runner/BackgroundRemoval/*.swift` files against the real iOS SDK.

Nothing was signed, archived, published or uploaded.

> **Accuracy note.** The first compile I triggered pointed at
> `migration/heroku-azure`, whose tip `7237347` contains **none** of this work — that
> green build proved nothing and is discarded. The build recorded above is the
> re-run against the correct branch. Its commit `8797269` is two commits behind local
> HEAD; `git diff 8797269..8634afc --name-only` is exactly
> `docs/bg/LOCAL_FIRST_BG_IMPLEMENTATION_PLAN.md` and
> `app/test/ui/wtm_add_garment_local_test.dart` — one Markdown file and one Dart
> **test** file, neither of which can affect iOS compilation.

---

## 2. Real-device results

**Android: DONE (2026-07-29).** See §0 for the full outcome — 31 consecutive runs,
0 SIGSEGV, 9 distinct images visually checked, median ~2.6 s, local ingestion
succeeding with items born `cutout_status=done` and no BiRefNet job.

| Platform | Status | Detail |
|---|---|---|
| Android | **VALIDATED** on a POCO X3 NFC (Android 11, arm64) | §0 |
| iOS | **NOT RUN** | No Mac and no iOS device. Distribution status is **unconfirmed** — see the note below. |

> **Apple Developer account status is unresolved, 2026-07-30.** This row
> originally said distribution was "still blocked on the Apple Developer
> account". That may no longer be true: a real Apple Team ID (`Z3YJ7Z29HT`) was
> committed to
> `deploy/site/.well-known/apple-app-site-association` on 2026-07-25 in
> `ce5321d` ("fix(ios): configure AASA with Apple Team ID"), which implies an
> active membership. The claim has **not** been confirmed with the owner, so it is
> marked unconfirmed rather than silently flipped in either direction. It gates
> iOS Phases 3–6 (`IOS_LOCAL_BG_PHASE_PLAN.md` §5).

So for **iOS**, none of the following has been observed on hardware: Apple Vision
output, cutout quality, preview latency, UI responsiveness, the iOS 17 runtime gate,
or on-device cache cleanup. The device script is `LOCAL_FIRST_BG_MANUAL_QA.md`.

## 3. Unavailable / not executed

| Item | Count | Status | Reason |
|---|---|---|---|
| Swift XCTest (`app/ios/RunnerTests/`) | **74 test functions** | **WRITTEN, NEVER EXECUTED** | Pre-existing arm64 blocker — see below |
| Android instrumented tests | 0 | Not written | Would need a device/emulator; the engine logic is covered by 83 JVM tests instead |
| Apple Vision on simulator | — | Not attempted | `VNGenerateForegroundInstanceMaskRequest` is unreliable on simulators; a green simulator run would not be evidence |

### 3.1 The iOS `RunnerTests` arm64 blocker — explicitly unresolved

`AppleVisionCutoutEngineTests.swift` (28), `LocalCutoutMaskTests.swift` (28) and
`LocalCutoutOperationCacheTests.swift` (18) — **74 test functions, 0 executed.**

The `ios-unit-tests` Codemagic workflow fails before a single assertion:

```text
Cannot test target "RunnerTests" on "iPhone 17 Pro":
RunnerTests does not support any of iPhone 17 Pro's architectures: arm64
```

This is a **pre-existing Flutter-template limitation, not a defect in the code under
test**: the scaffolded `RunnerTests` target has no `baseConfigurationReference` (so it
never inherits `Flutter/Generated.xcconfig`), and the project pins
`SDKROOT = iphoneos` with `SUPPORTED_PLATFORMS = iphoneos` in Release/Profile, so the
target is not configured to build for an arm64 **simulator**. The target has never
been executed in this repository — its only prior content was the template
`testExample`.

Fixing it means changing project-level architecture/platform settings. That is an
owner decision with three options in
`LOCAL_FIRST_BG_IMPLEMENTATION_PLAN.md` §8c. **It was not attempted**, and the
workflow was left manual-only so it cannot break any push.

> **Correction, 2026-07-30 — the architecture failure is only half of it.** The
> three test files reference 9 app-target types across 91 call sites but import
> only `CoreGraphics` / `CoreVideo` / `XCTest`: there is **no
> `@testable import Runner`**, and the app sources are not members of the
> `RunnerTests` target. Those types are Swift-default `internal`, so the target
> cannot compile on any destination. The architecture error masked it, because
> Xcode aborts on destination selection before compiling. Both layers are being
> addressed in iOS Phase 1 — see `IOS_LOCAL_BG_PHASE_PLAN.md` §1.

**Do not read "iOS compile passed" as "the Swift tests passed."** The Swift logic —
mask maths, `instanceMask` label-map handling, pixel-buffer safety, cache
containment — is currently verified only by code review and by compilation.

---

## 4. Measured timings

### 4.1 Measured

| Path | Metric | Value | Source |
|---|---|---|---|
| Azure BiRefNet Lite (the fallback) | model init | **46.7 s** (cold, scale-to-zero) | `wtm-rembg-job` canary, 4 vCPU / 8 GiB, 2026-07-23 |
| Azure BiRefNet Lite | inference | **12.2 s** | same canary |
| Azure BiRefNet Lite | peak RSS | **7.0 GiB** of 8 GiB | same canary — ~1 GiB headroom; 6 GiB would OOM |

These are the *existing* cloud path, measured during earlier BiRefNet work, and are
reproduced here as the baseline the local path must beat. They were **not**
re-measured in this phase.

### 4.2 Measured on device — Android

| Device | Engine | Inference | Total | Result |
|---|---|---|---|---|
| POCO X3 NFC, Android 11, arm64 | ML Kit Subject Segmentation `16.0.0-beta1`, per-subject masks | **639–797 ms** | min 1804 / **median ~2612 ms** / max 2703 | **31/31 runs succeeded** |

Against the BiRefNet baseline in §4.1 (12.2 s inference plus up to 46.7 s cold init)
that is roughly a **5–18× speedup**.

| Device | Engine | Result |
|---|---|---|
| _(iOS 17+, model TBD)_ | Apple Vision | **NOT MEASURED** |

No estimate is offered for iOS. An invented number would be worse than a blank.

### 4.3 Quality thresholds — shipped but unvalidated

`local_cutout_quality_policy.dart` ships these. They were chosen conservatively from
the spec, **not** tuned against real device output, and were deliberately left
untuned rather than fitted to fabricated results:

| Threshold | Value | Effect |
|---|---|---|
| `minForegroundAreaRatio` | 0.01 | hard reject → cloud fallback |
| `maxForegroundAreaRatio` | 0.995 | hard reject → cloud fallback |
| `softMaxBorderForegroundRatio` | 0.40 | warning only |
| `softMaxUncertainPixelRatio` | 0.35 | warning only |
| `softMinMeanForegroundConfidence` | 0.55 | warning only |
| `softMinBoundsAreaRatio` | 0.02 | warning only |

Only the two hard bounds can reject a result; every soft threshold merely warns, so a
mis-set soft value cannot cost a user their cutout. Tune only with real measurements
from §4.2.

---

## 5. Gate audit — every new flag proven OFF

| Gate | Layer | Default | In production? | Evidence |
|---|---|---|---|---|
| `LOCAL_BG_REMOVAL_ENABLED` | Dart | `false` | absent from `app/env/prod.json` | `feature_gates.dart:26` |
| `LOCAL_BG_ANDROID_ENABLED` | Dart | `false` | absent | `feature_gates.dart:35` |
| `LOCAL_BG_IOS_ENABLED` | Dart | `false` | absent | `feature_gates.dart:43` |
| `LOCAL_CUTOUT_UPLOAD_ENABLED` | backend | `False` | **NOT SET** on `wtm-api-prod` | `config.py:151`; `heroku config` |
| `LOCAL_CUTOUT_IMPROVE_ENABLED` | backend | `False` | **NOT SET** on `wtm-api-prod` | `config.py:156`; `heroku config` |

Verified by construction, not by reading comments:

```text
Settings(_env_file=None) with the vars unset →
  local_cutout_upload_enabled  = False
  local_cutout_improve_enabled = False
```

`CUTOUT_EDITOR_ENABLED=true` **is** set in production and in `app/env/prod.json` —
that is the **pre-existing** Fix cutout editor, added by `b6eb05a` and live since
Heroku v14 (2026-07-23). It is not one of this feature's gates and was not changed.

Both sides must be on for anything to happen. With the backend gate off the new
endpoints 404 and the app uses the unchanged `POST /v1/wardrobe` → Azure BiRefNet
path.

---

## 6. Cost, dependency and licence audit

**No paid provider was added.** `grep` across every new file under
`local_cutout/`, `BackgroundRemoval/` and `background/` returns no reference to
FASHN, Replicate, Bria or any API key.

| Dependency | Kind | Cost | Licence | Recorded |
|---|---|---|---|---|
| `com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1` | runtime, Android | **free** — on-device, Play-services delivered | ML Kit ToS, commercial use permitted | `LICENSES.md:62` |
| Apple `Vision` framework | runtime, iOS | **free** — part of iOS | Apple SDK licence | `LICENSES.md:64` |
| `junit:junit:4.13.2` | **test only** | free | EPL-1.0, never shipped | `LICENSES.md:63` |

No new Flutter package, no new CocoaPod, no new Python package. No model weights
ship in the APK — ML Kit's model is delivered by Google Play services, so the user
installs no extra app. `minSdk` moved 23 → 24 (ML Kit's floor; owner-approved in
Phase 3), and `pubspec.yaml`'s `min_sdk_android` was kept in sync.

---

## 7. Regression coverage — existing flows unchanged

All of the following pre-existing suites pass unmodified, which is the evidence that
the dormant feature changes nothing:

| Flow | Suite | Result |
|---|---|---|
| Add Garment (cloud path) | `features/add_wardrobe_item_screen_test.dart` | pass |
| Cutout wait / polling | `features/wardrobe_cutout_wait_test.dart`, `features/wardrobe_polling_test.dart` | pass |
| Wardrobe screen & delete | `features/wardrobe_screen_test.dart`, `features/wardrobe_remove_item_test.dart` | pass |
| Closet + Enhance paywall | `ui/wtm_closet_test.dart` | pass |
| Wardrobe repository | `data/wardrobe_repository_test.dart` | pass |
| AI Enhance | `data/wardrobe_item_enhance_test.dart` | pass |
| Try-on / studio | `features/studio_ui_test.dart`, `features/tryon_studio_test.dart` | pass |
| Fix cutout gate | `ui/wtm_cutout_gate_test.dart` | pass |
| BG worker & pipeline | `test_bg.py`, `test_bg_pipeline.py`, `test_bg_worker.py` | 146 pass (with the rest of the group) |
| Split workers / recovery | `test_split_workers.py`, `test_worker.py` | pass |
| Wardrobe API | `test_wardrobe.py` (29) | pass |
| Editor mask ingest | `test_mask_ingest.py` (13) | pass |

`wtm_add_garment_local_test.dart` additionally asserts the *negative* cases directly:
with the gate off the native engine is never called and the cloud path runs
byte-for-byte as before; AI Enhance is offered but never invoked by a local add
(proved by a repository that throws if `enhanceItem` is ever reached); and an upload
with no object key falls through to the legacy cloud create.

### 7.1 Device QA results

**Android: complete** — §0. **iOS: pending**; paste the completed
`LOCAL_FIRST_BG_MANUAL_QA.md` §12 table here before any iOS activation. Leave it
empty rather than optimistic.

## 8. Privacy audit

| Surface | Finding |
|---|---|
| Flutter analytics | 26 forbidden keys asserted **absent** from every payload builder — `width`, `height`, `operationId`, every `*path*`/`file`/`filename`, `objectKey`, `url`, `token`, `engineVersion`, `message`, `error`, `exception`, `stackTrace`, `metadata`, `exif`. Values are also checked, e.g. exact dimensions `1601`/`1199` must not appear. 21 tests. |
| Kotlin | **Zero** log calls carry a path, URI, object key or filename. |
| Swift | Logs carry only bounded enum `code.rawValue` and stage durations (`decode_ms`, `inference_ms`, `mask_ms`, `composite_ms`, `write_ms`). |
| Backend | Logs carry storage status codes and exception **type names** (`type(exc).__name__`), never an object key or signed URL. |
| Error contract | `SOURCE_MISSING` (422) and `PROVIDER_ERROR` (503) carry no object key and no signed URL. |
| Retention | Device scratch files live in `<app cache>/wtm-local-cutout/<operation-id>/`, swept after 6 h. Cleanup is **by operation id only** — there is no path-based delete API on either platform, so a malicious or buggy path can never be handed to a delete call. |
| Deletion | Item and account deletion already sweep every `media_assets` role, so `cutout_mask` objects are erased with the rest. No new deletion code. |

---

## 9. Confirmations

| Requirement | Status |
|---|---|
| No deployment | **Confirmed.** `wtm-api-prod` is at **v16, released 2026-07-24** — before this work began. Nothing was pushed to Heroku or Azure. |
| No production flag activated | **Confirmed.** Both new backend gates are `NOT SET` on `wtm-api-prod`. |
| No version bump | **Confirmed.** `1.0.15+18` on HEAD, on `main`, and on `origin/migration/heroku-azure` — identical. |
| No store upload | **Confirmed.** Only a **debug** APK was built, locally, and never installed anywhere. No AAB, no IPA, no archive, no TestFlight. |
| Codemagic used as compile runner only | **Confirmed.** `ios-compile-check` builds `--no-codesign`; nothing published. |
| Clean git state after commit | See §10. |

---

## 10. Known risks and blockers

Ordered by what should worry an operator most.

1. **A native SIGSEGV inside ML Kit bypasses the typed fallback entirely.** The
   process dies; no Kotlin or Dart handler can catch it. One was observed in
   `dl-MlkitSubjectSegmentation` while the foreground mask was still enabled; **0 in
   31 runs** since it was dropped. Encouraging, not proof of absence. This is now the
   top Android risk, and it is the reason this document does not claim every possible
   failure is catchable.
2. **iOS has never run local inference.** Apple Vision is verified against fakes and
   by compilation only. **Blocker for iOS activation** (Android is validated, §0).
3. **74 Swift tests have never executed** (arm64 blocker, §3.1). Pre-existing project
   limitation; fixing it is an owner decision. iOS mask maths and pixel-buffer safety
   rest on review + compile only.
4. **ML Kit Subject Segmentation is `16.0.0-beta1`**, and its full
   `foregroundConfidenceMask` is *already known bad* on this device (§0). We now use
   per-subject masks only. Those are **not normalised** — the `[-0.183, 1.180]`
   envelope was established by measurement, not documentation, so a future SDK release
   could move it. The zero-tolerance safety range means that degrades to a typed
   fallback rather than a bad cutout. Re-check for a stable release before enabling
   Android.
5. **Dart-side quality thresholds are still unvalidated** (§4.3). The Android engine
   now enforces its own coverage band natively (`0.005..0.995`), so a mask the server
   would refuse never leaves the device; the Dart soft thresholds remain untuned.
6. **`minSdk` 23 → 24** drops Android 6.0 devices from future releases. Owner-approved
   in Phase 3, but it is a real, permanent audience change and takes effect on the
   next store build whether or not the gates are on.
7. **iOS needs a 17.0+ runtime.** Deployment target stays 15.5; 15.5–16.x report
   `unsupported_os` and use the cloud path — correct, but it means a meaningful share
   of iOS users get no benefit.
8. **Pre-existing, not caused here:** `lib/armeabi-v7a/libxeno_native.so` (from
   `mediapipe-internal` via the already-shipped `google_mlkit_pose_detection`) has
   4 KB ELF alignment and is not 16 KB page-size compatible. **32-bit only** — both
   64-bit ABIs pass, and 16 KB pages are a 64-bit concern. Verified present in the
   2026-07-24 release APK, before this work. No toolchain change was made; upgrading
   ours cannot fix a Google-published `.aar`.
9. **Two env backups were committed by accident** in `8797269`
   (`app/env/prod.json.bak-*`). `.gitignore` had `app/env/*.json`, which does not
   match `prod.json.bak-<timestamp>`. Fixed in Phase 8: both untracked, the ignore
   rule widened. **Exposure assessed as low** — the populated values
   (`API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `POSTHOG_HOST`,
   `REVENUECAT_ANDROID_KEY`, `REVENUECAT_ENTITLEMENT_ID`) are all public
   client-side values that ship inside every published APK by construction, and the
   genuinely secret slots (`SENTRY_DSN`, `POSTHOG_API_KEY`, `GOOGLE_WEB_CLIENT_ID`)
   were **empty**. The values nonetheless remain in this branch's history at
   `8797269`; removing them would need a history rewrite of a pushed branch, which is
   the owner's call and was **not** performed.

---

## 11. Recommendation

Merge and deploy are safe — the feature is inert with all five gates OFF. **Activation
is a separate decision, and the two platforms are now in very different places.**

**Android** is validated on device (§0) and works end to end. Before flipping its
gates:

1. Accept, in writing, the residual **native-crash risk**: a SIGSEGV inside ML Kit
   cannot be caught, so it kills the app rather than falling back. 0 in 31 runs.
2. Re-check ML Kit Subject Segmentation for a **stable release** — we are relying on
   `16.0.0-beta1` and on per-subject mask behaviour that is undocumented.
3. Follow the staged order in `LOCAL_FIRST_BG_ROLLOUT_RUNBOOK.md`; prefer a staged
   Play rollout and watch the analytics between steps.

**iOS** is not ready and must not be enabled. It needs:

1. A device run of `LOCAL_FIRST_BG_MANUAL_QA.md` — currently impossible; distribution
   is blocked on the Apple Developer account.
2. A decision on the `RunnerTests` arm64 question (plan §8c), or written acceptance
   that the iOS engine ships with 74 unexecuted tests.

Never enable both platforms in the same release.
