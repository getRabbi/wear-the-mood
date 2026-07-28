# Local-first background removal — validation & release-candidate report

**Branch** `feat/local-first-background-removal`
**Validated commit** `8634afc` (local), `8797269` (tip pushed to `origin`)
**Date** 2026-07-28
**Verdict** **NOT ready for production activation.** Every automated suite passes and
both platforms compile, but **no device has ever executed local inference**. The
feature ships dormant behind five default-OFF gates, so the branch is safe to merge
and safe to deploy — it just must not be *switched on* until the device QA in
`LOCAL_FIRST_BG_MANUAL_QA.md` is run and its results recorded here.

This report deliberately separates four things: **passed**, **real-device**,
**unavailable**, and **risks**. Nothing unexecuted is described as passing.

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
| `gradlew :app:cleanTestDebugUnitTest :app:testDebugUnitTest` | **83 passed, 0 failures, 0 errors** |
| `flutter build apk --debug --dart-define-from-file=env/prod.json` | **BUILD SUCCESSFUL** |

`cleanTest` was required: a plain `testDebugUnitTest` reported `UP-TO-DATE` from the
Phase 3 cache, which is not an execution. Per-suite, from the JUnit XML:

| Suite | Tests |
|---|---|
| `GoogleSubjectSegmenterEngineTest` | 35 |
| `SoftMaskTest` | 22 |
| `LocalCutoutCacheStoreTest` | 16 |
| `SingleOperationGuardTest` | 10 |

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

**None. No device test has been run.**

| Platform | Status | Why |
|---|---|---|
| Android | **NOT RUN** | `adb devices` lists no device. Nothing was installed anywhere. |
| iOS | **NOT RUN** | No Mac, no iOS device, and iOS distribution is still blocked on the Apple Developer account — no TestFlight, so the build cannot even be installed. |

Consequently **zero** of the following has been observed on hardware: ML Kit
Subject Segmentation output, Apple Vision output, cutout quality, local preview
latency, UI responsiveness during segmentation, Play-services model download, the
iOS 17 runtime gate, or on-device cache cleanup.

The exact device script to close this gap is `LOCAL_FIRST_BG_MANUAL_QA.md`. Until
its results are pasted into §7 below, this feature is not activation-ready.

---

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

### 4.2 NOT measured — must be filled from device QA

| Device | Engine | Prepare | Inference | Preview visible | Result |
|---|---|---|---|---|---|
| _(Android, model TBD)_ | ML Kit Subject Segmentation | — | — | — | **NOT MEASURED** |
| _(iOS 17+, model TBD)_ | Apple Vision | — | — | — | **NOT MEASURED** |

No estimate is offered. An invented number here would be worse than a blank.

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

### 7.1 Device QA results — **PENDING**

_Paste the completed `LOCAL_FIRST_BG_MANUAL_QA.md` result table here before any
activation. Leave it empty rather than optimistic._

---

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

1. **No device has ever run local inference.** The single largest gap. Both engines
   are verified against fakes and by compilation only. **Blocker for activation.**
2. **74 Swift tests have never executed** (arm64 blocker, §3.1). Pre-existing project
   limitation; fixing it is an owner decision. iOS mask maths and pixel-buffer safety
   rest on review + compile only.
3. **ML Kit Subject Segmentation is `16.0.0-beta1`** — the only pre-release
   dependency in the build. Google has shipped no stable release. Mitigated: gated
   off, every failure typed, degrades to BiRefNet. Re-check for stable before
   enabling Android.
4. **Quality thresholds are unvalidated** (§4.3). Only two hard bounds can reject;
   soft ones merely warn, so the blast radius is a fallback rather than a bad cutout.
5. **`minSdk` 23 → 24** drops Android 6.0 devices from future releases. Owner-approved
   in Phase 3, but it is a real, permanent audience change and takes effect on the
   next store build whether or not the gates are on.
6. **iOS needs a 17.0+ runtime.** Deployment target stays 15.5; 15.5–16.x report
   `unsupported_os` and use the cloud path — correct, but it means a meaningful share
   of iOS users get no benefit.
7. **Pre-existing, not caused here:** `lib/armeabi-v7a/libxeno_native.so` (from
   `mediapipe-internal` via the already-shipped `google_mlkit_pose_detection`) has
   4 KB ELF alignment and is not 16 KB page-size compatible. **32-bit only** — both
   64-bit ABIs pass, and 16 KB pages are a 64-bit concern. Verified present in the
   2026-07-24 release APK, before this work. No toolchain change was made; upgrading
   ours cannot fix a Google-published `.aar`.
8. **Two env backups were committed by accident** in `8797269`
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

Merge and deploy are safe — the feature is inert. **Activation is not.**

Minimum before flipping the first gate:

1. Run `LOCAL_FIRST_BG_MANUAL_QA.md` on at least one Android 24+ device and one
   iOS 17+ device; paste the results into §7.1 and the timings into §4.2.
2. Decide the `RunnerTests` arm64 question (plan §8c) — or accept, in writing, that
   the iOS engine ships with 74 unexecuted tests.
3. Re-check ML Kit Subject Segmentation for a stable release.
4. Follow the staged order in `LOCAL_FIRST_BG_ROLLOUT_RUNBOOK.md` (Phase 9, not yet
   written) — never both platforms at once.
