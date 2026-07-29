# iOS local-first background removal — production-readiness phase plan

> Approved 2026-07-30. Companion to `LOCAL_FIRST_BG_IMPLEMENTATION_PLAN.md` (which
> covers the cross-platform design) and `LOCAL_FIRST_BG_ROLLOUT_RUNBOOK.md` (which
> covers flag rollout). This file is the iOS-specific work plan and the record of
> what was actually verified at each step.
>
> **Android is finished and must not regress.** Local-first background removal
> shipped ON for Android in 1.0.16+19 (Play production, 2026-07-29). Nothing in
> this plan may alter Android code, Android gates, or the shared backend contract.

---

## 0. Starting state (audited 2026-07-29/30 at `993d760`)

| Item | State |
|---|---|
| iOS engine code | **Complete in `app/ios/Runner/BackgroundRemoval/` (6 Swift files)** |
| Vision API used | `VNGenerateForegroundInstanceMaskRequest` → `allInstances` → `generateScaledMaskForImage(forInstances:from:)`, one shared `VNImageRequestHandler` |
| `instanceMask` as alpha | **Not used** — correctly documented as an instance-label map |
| iOS 15.5–16.x | Typed `unsupported_os` via an injected availability probe; deployment floor stays 15.5 |
| Channel contract | `wtm/background_removal`, 32-char lowercase-hex operation ids, cleanup by **id only** — identical to Android |
| Error/metric parity | Swift error raw values, availability values and metric formulas all match Dart and `SoftMask.kt` exactly |
| Backend | **Already compatible** — `_LOCAL_ENGINES` includes `apple_vision`, `_LOCAL_PLATFORMS` includes `ios`. No server change needed for iOS. |
| `LOCAL_BG_IOS_ENABLED` | **`false`** — dormant, and stays that way until Phase 6 |
| Real Vision inference | **Never executed on hardware** |
| Swift XCTest | **74 functions written, 0 ever executed** |

Baseline suites at `993d760`: Flutter **818 passed**; backend **787 passed, 1 skipped**;
Android **144 Kotlin `@Test`** (unchanged, the regression gate).

**Compilation is not validation.** `ios-compile-check` has been green for months
while the Swift tests never ran and Vision never executed. Android shipped a
mask that compiled, passed its tests, and was still corrupt on the first device
run — the per-subject fix (`958a56f`) exists because of it. iOS gets no benefit
of the doubt.

---

## 1. The RunnerTests blocker — two layers

### Layer 1 — the target will not build for an arm64 simulator (documented)

`ios-unit-tests` fails before the first assertion:

```text
Cannot test target "RunnerTests" on "iPhone 17 Pro":
RunnerTests does not support any of iPhone 17 Pro's architectures: arm64
```

The *recorded* cause was: `RunnerTests`' three build configurations carry no
`baseConfigurationReference`, so the target never inherits
`Flutter/Generated.xcconfig`; and the project pins `SDKROOT = iphoneos` with
`SUPPORTED_PLATFORMS = iphoneos` in Release/Profile.

**Measured on Codemagic 2026-07-30 (build `6a6a4297`, commit `fda5d6c`) — that
diagnosis is wrong.** Both halves of it are false at build time:

* CocoaPods **does** attach a base configuration during `pod install`. The
  generated `Pods-RunnerTests.{debug,release,profile}.xcconfig` files exist and
  are wired into the three configurations.
* The target resolves `SUPPORTED_PLATFORMS = iphoneos iphonesimulator` and
  `SDKROOT = iphonesimulator26.4` — simulator support is present.

The real cause is a single inherited setting. Side by side, Debug /
`iphonesimulator`:

| Setting | `RunnerTests` | `Runner` (host) |
|---|---|---|
| `ARCHS` | **`x86_64`** | `arm64 x86_64` |
| `EXCLUDED_ARCHS` | **`arm64`** | `i386` |
| `VALID_ARCHS` | `arm64 x86_64` | — |
| `NATIVE_ARCH` | `arm64` | — |
| `SUPPORTED_PLATFORMS` | `iphoneos iphonesimulator` | `iphoneos iphonesimulator` |
| `ENABLE_TESTABILITY` | `YES` | `YES` |
| `IPHONEOS_DEPLOYMENT_TARGET` | `15.5` | `15.5` |
| `PRODUCT_MODULE_NAME` | `RunnerTests` | `Runner` |

The generated Pods xcconfig sets `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`,
which reduces the target to `x86_64`. Every simulator the `mac_mini_m2` image
offers is arm64 (iPhone 17 Pro, 17 Pro Max, 17e, Air, 17), so there is no
architecture in common — exactly the reported error.

**Fix (`9f4f794`):** override `EXCLUDED_ARCHS[sdk=iphonesimulator*]` to empty in
the three `RunnerTests` build configurations. A target-level build setting beats
its `baseConfigurationReference`, so this needs no edit to shared or release
configuration, and no change to `SDKROOT`, `SUPPORTED_PLATFORMS`, the 15.5
deployment target, the `Runner` bundle id, signing, entitlements or capabilities.
The exclusion is meaningless for this target anyway: `inherit! :search_paths`
means `RunnerTests` takes search paths from the pods and links none of them, and
the host app already builds arm64 simulator against the same pods.

### Layer 2 — the tests cannot compile (previously undocumented)

Independent of Layer 1, and fatal on its own. The three test files reference
**9 app-target types across 91 call sites**:

| Type | References |
|---|---|
| `LocalCutoutOperationCache` | 21 |
| `PixelBufferMaskCompositor` | 20 |
| `LocalCutoutMaskMath` | 16 |
| `LocalCutoutError` | 14 |
| `LocalCutoutOperationGuard` | 9 |
| `AppleVisionCutoutEngine` | 6 |
| `LocalCutoutAvailability` | 3 |
| `ProducedForegroundMask` | 2 |
| `ForegroundMaskProducing` | 2 |

Their complete import lists are `CoreGraphics` / `CoreVideo` / `XCTest` — there is
**no `@testable import Runner` in any of them**, and the app sources are not
members of the `RunnerTests` target (its Sources phase holds only the four test
files). Every one of those types is Swift-default `internal`, therefore invisible
outside the `Runner` module.

Layer 1 masked Layer 2: Xcode aborts on destination/architecture before it
compiles a line, so the ~91 "cannot find type in scope" errors have never been
seen. `ENABLE_TESTABILITY = YES` is already set on the project Debug
configuration (`:528`), so the fix is available — it was simply never applied.

### Layer 3 — a hypothesis the measurement did not support

The project uses Flutter's **SwiftPM** integration
(`XCLocalSwiftPackageReference` → `FlutterGeneratedPluginSwiftPackage`,
`:686-698`), and that package product is attached to **`Runner` only**
(`:210-212`); `RunnerTests` has no `packageProductDependencies`. Since
`RunnerTests.swift` does `import Flutter`, the concern was that the Podfile's
`inherit! :search_paths` might no longer supply Flutter to the test bundle.

**The diagnostic did not support this.** `RunnerTests` resolves a populated
`FRAMEWORK_SEARCH_PATHS` covering the built products directory and every pod
framework, and `BUNDLE_LOADER` / `TEST_HOST` both point at the built `Runner.app`
binary. Per the standing rule that Flutter is connected to `RunnerTests` **only
if the measured build output proves it is required**, no SwiftPM dependency was
added. If a Flutter-module resolution error appears once the target compiles,
this is the first thing to revisit.

---

## 2. Phases

Each phase ends with: tests run, a commit, a report, and a stop for approval.
No phase begins before the previous one is approved.

### Phase 1 — make the Swift tests genuinely execute

* Measure first: `xcodebuild -showBuildSettings` for `RunnerTests` against an
  arm64 simulator, reporting `SDKROOT`, `SUPPORTED_PLATFORMS`, `ARCHS`,
  `EXCLUDED_ARCHS`, `baseConfigurationReference`, `TEST_HOST`, `BUNDLE_LOADER`
  and the Swift module/search-path configuration.
* Fix **at target scope only**. Deployment target stays 15.5; the `Runner`
  bundle id, signing, entitlements and capabilities are untouched.
* Add `@testable import Runner` to the three test files.
* Attach Flutter to `RunnerTests` **only if** the measured output proves it is
  required.
* No test may be deleted, skipped or `XCTSkip`-ed to make the suite pass.
* **Exit criteria:** 74 functions compile and execute; exact
  executed/passed/failed/skipped counts reported; no architecture and no
  "cannot find type in scope" errors; `ios-compile-check` still green; Flutter
  green; Android gates ON; iOS gate OFF.

### Phase 2 — harden the Apple Vision engine

* **Port Android's corruption guard.** `SoftMask.kt` gained
  `inspectConfidence` / `requireUsableConfidence` /
  `MAX_INVALID_CONFIDENCE_RATIO = 0.001` in `582b44e` and `958a56f`, after a
  device diagnostic measured a **69 % invalid** confidence buffer. iOS was last
  touched at `78ff69b`, *before* those commits, and has no equivalent: its float
  path silently maps NaN→0 and clamps out-of-range values, so a corrupt Vision
  buffer would become a plausible-looking mask instead of a typed fallback.
  This is the single most important Phase 2 item.
* Strict pre-accept output validation: source/mask/cutout dimensions equal,
  meaningful subject count, both PNGs re-decode, cache files exist and are
  non-empty, no invalid pixel-buffer access. Anything failing becomes a **typed
  fallback**, never a saved item.
* Re-audit orientation, handler usage, pixel format, plane count,
  `bytesPerRow`, lock/unlock pairing, compositing, PNG encoding, cache
  containment, timeout, cancellation, exactly-once callback, detach and
  background-thread execution.
* New Swift tests for every added guard.

### Phase 3 — physical-iPhone diagnostic validation

Not broad UI testing. A debug-only artifact export (**none exists today — it must
be written**) capturing, from one operation: the exact compressed input, the
authoritative scaled-mask PNG, the transparent cutout PNG, privacy-safe
dimensions / pixel format / bytes-per-row / timings, and a device screenshot.

Inspect the eight stages separately: input decode → Vision observation →
scaled-mask generation → mask extraction → compositing → PNG output → Flutter
display → backend local ingestion.

The diagnostic build must make a local failure **visible**, not silently hidden
behind BiRefNet. Normal typed fallback is restored once a correct result is
obtained.

### Phase 4 — end-to-end local iOS flow

At least **20 consecutive operations across at least 8 distinct images**: normal
garment, dark garment, light garment on a light background, thin straps/lace,
complex sleeves, multiple nearby objects, portrait/person, non-garment object.

Verify local preview before cloud, `/v1/wardrobe/local-cutout` success, item born
`cutout_status=done`, no legacy `/v1/wardrobe` call, no Azure BiRefNet job,
transparent and correct saved cutout, `sourceMissing` reselect, cancellation and
disposal clearing the operation cache, Fix-cutout still separate, Improve-edges
preserving the existing cutout, Android and backend unchanged. Reuses
`LOCAL_FIRST_BG_MANUAL_QA.md` §6 and §12. Timing, quality, fallback and crash
results recorded honestly.

### Phase 5 — iOS authentication and UI readiness

In a production-configured internal build: Google auth against the **iOS** OAuth
client (verified directly — bundle id, URL scheme, reversed client id, authorized
client, signing — never assumed from Android), Supabase audience, callback
returning to the app, session created and persisted, Home opening automatically,
logout, Sign in with Apple, email/password unaffected, no redirect loop, no
legacy UI, no half-screen/clipping/keyboard/safe-area defects on Home, Add
Garment, Closet and Profile.

### Phase 6 — TestFlight release preparation

`LOCAL_BG_IOS_ENABLED=true` in the **internal TestFlight build only** — never
globally for App Store users. Android configuration unchanged; backend unchanged.
Full Flutter, backend, Android-regression, Swift and iOS compile suites. iOS
build number incremented only when release validation is complete. Upload, then
test the TestFlight-delivered build on a physical iPhone: auth, local cutout,
fallback, UI, push and relaunch. **No App Store submission before TestFlight
device QA passes.**

---

## 3. Standing safety restrictions

* Do not modify the Android ML Kit per-subject path.
* Do not turn Android production gates OFF.
* Do not alter production user data.
* Do not change R2, Azure, Heroku or Supabase architecture.
* Do not add a paid background-removal provider.
* Do not enable iOS local background removal in production before physical-device
  validation.
* Do not claim "perfect", "fully safe" or "all tests passed" when a device test or
  a Swift test was not executed.
* Stop and report unclear API behaviour, mask corruption, crashes, signing issues
  or authentication mismatches instead of guessing.

## 4. Android regression protections

* No changes to `app/android/**`, `SoftMask.kt`,
  `GoogleSubjectSegmenterEngine.kt`, `MlKitSubjectSegmentationClient.kt`, or the
  `subject_segment` manifest meta-data (`AndroidManifest.xml:74-75`).
* No changes to `LOCAL_BG_REMOVAL_ENABLED` / `LOCAL_BG_ANDROID_ENABLED`; the
  `codemagic.yaml` required-gate guard (`993d760`) stays in force.
* `/v1/wardrobe/local-cutout` is not modified — iOS needs no server change, so
  Android compatibility is preserved structurally rather than by promise.
* Regression gate every phase: 144 Kotlin `@Test` across the nine
  `background/*Test.kt` files, plus the Flutter suite.

## 5. Open owner questions

1. **Apple Developer account / TestFlight.** A real Team ID (`Z3YJ7Z29HT`) was
   committed on 2026-07-25 (`ce5321d`), but `LOCAL_FIRST_BG_TEST_REPORT.md`,
   `LOCAL_FIRST_BG_ROLLOUT_RUNBOOK.md` and `docs/IOS_APPSTORE_READINESS.md` still
   describe the account as an open blocker. Confirmation needed before Phase 3.
2. **Physical iPhone running iOS 17+** for Phases 3–5. Phases 1 and 2 run on
   Codemagic and need neither.

## 6. Phase log

| Phase | Status | Evidence |
|---|---|---|
| 0 — audit | ✅ approved 2026-07-30 | Findings recorded in §0 and §1 |
| 1 — Swift tests execute | in progress | — |
| 2 — engine hardening | not started | — |
| 3 — device diagnostics | not started | blocked on §5 |
| 4 — end-to-end flow | not started | blocked on §5 |
| 5 — auth + UI | not started | blocked on §5 |
| 6 — TestFlight | not started | blocked on §5 |
