# Local-first background removal — operations

The invariants that keep on-device background removal alive in production, the
alerts that make a release-wide outage visible, and the procedures for the two
things an operator actually has to do: switch it off in an incident, and switch it
back on.

Companion documents: `LOCAL_FIRST_BG_ROLLOUT_RUNBOOK.md` (staged rollout),
`IOS_LOCAL_BG_PHASE_PLAN.md` (the iOS activation phases),
`LOCAL_FIRST_BG_IMPLEMENTATION_PLAN.md` (design).

---

## 1. Why this document exists

The feature "stopped working" several times. **Only once was the engine at fault.**

| # | What was reported | What it actually was | Why nothing caught it |
|---|---|---|---|
| 1 | "ML Kit is broken on Android" | `FabricTile` painted an opaque swatch, radial shade and sheen *behind* every image, filling in every transparent pixel | ML Kit, the mask, the backend and R2 were all provably correct at artifact level. A presentation defect in shared Flutter code. |
| 2 | "Every ingest fails with 422" | `encodeMaskPng` wrote the confidence into R/G/B and left alpha opaque; the server reads alpha first, measured coverage 1.0, and rejected everything | 83 green Kotlin tests. The only coverage of the encoder was a fake that returned a canned byte array. |
| 3 | "iOS local removal does nothing" | `encodeCutoutPNG` composed through a `CGBitmapContext` in a pixel format CoreGraphics cannot represent, so it returned `nil` on **every device, every time, since it was written** | A green `ios-compile-check`, 75 "green" Swift tests that had never executed, and a typed cloud fallback that produced a normal-looking result. |
| 4 | "Improve edges says not found" | The button was gated on the local-BG **master** flag while the server gates that endpoint separately, so shipping Android ML Kit switched on a button whose endpoint answers 404 | Two independent flags, no check that they agreed. |
| 5 | Genuine engine failure | ML Kit's `foregroundConfidenceMask` returns a materially corrupt buffer on `16.0.0-beta1` — measured 15–96 % NaN/out-of-range in row-shaped blocks | Nothing; this one was a real provider defect, found by device diagnostics. |

Four of five were **configuration or presentation**, not the engine. Every one of
them produced the same symptoms: a green build, a healthy API, a successful save,
and a garment that took ~90 s instead of ~5 s. The cloud fallback worked perfectly
and that is exactly what hid them.

So the guarantee this system buys is **not** "it can never break". It is narrower
and checkable:

* a broken local engine **cannot silently ship** — the release verifier and the
  native self-test both look at what the encoders actually produce;
* a release-wide outage **cannot stay invisible** — the operation event records
  local attempts on every add, including successful cloud fallbacks;
* an individual failure **still falls back safely** — one bad photo or one odd
  device is a typed fallback, never an error the user sees;
* production builds **contain and activate both engines** — the gates are a
  committed file, asserted against the artifact before it ships;
* every relevant dependency update **forces revalidation** — device evidence is
  keyed to a hash of the native sources plus the toolchain manifest.

---

## 2. The production contract

### Application (`app/env/feature_policy.prod.json`, committed)

```
LOCAL_BG_REMOVAL_ENABLED=true
LOCAL_BG_ANDROID_ENABLED=true
LOCAL_BG_IOS_ENABLED=true
LOCAL_BG_IOS_DIAGNOSTICS_ENABLED=false
```

`app/env/prod.json` is **generated**, never hand-maintained:

```bash
# CI (credentials from the Codemagic app_prod_config env group)
python3 scripts/render_app_env.py --profile prod --credentials env

# locally (credentials preserved from the existing untracked file)
python3 scripts/render_app_env.py --profile prod --credentials file
```

The local form is idempotent and self-healing: it keeps every credential already
in `app/env/prod.json` and rewrites the gates from the committed policy, so a
drifted or truncated config snaps back to the invariant instead of shipping.
`build_prod.ps1` runs it automatically.

### Backend

```
LOCAL_CUTOUT_UPLOAD_ENABLED=true      # required; `false` refuses to boot in prod
LOCAL_CUTOUT_EMERGENCY_DISABLE=false  # default; the ONLY supported way to switch off
```

A production process **refuses to start** when the ingestion gate is `false`
without the emergency switch. Requiring the variable merely to *exist* closed only
half the hole — `false` is well-formed and produces exactly the same total outage.

Cloud BiRefNet fallback is never removed or weakened. It stays the automatic path
for every typed local failure.

---

## 3. Alerts

Read from the `local_bg_operation` event (one per Add Garment, on every path) and
`local_bg_self_test` (once per app version per install). Every property is a
bounded enum, a bucket or a boolean — no image bytes, paths, URLs, filenames,
addresses, account names or device identifiers.

### Page immediately — these mean *we* broke it

| Condition | Why it pages |
|---|---|
| `local_attempted` rate on a supported platform drops **> 50 % release over release** | The signature of a gate compiled off or a channel not registered. Every add still succeeds, so nothing else fires. |
| `health = channelUnavailable` appears at all in a **production** build | The native engine was not compiled in or not registered. Impossible on a correct build. |
| `local_gate_enabled = false` on a production build | The artifact shipped with the feature compiled off. |
| `local_bg_self_test` with `status = fail` | A real encoder/cache/provider defect on real devices. The single highest-signal event here. |
| `backend_status_category = gate_off` | The endpoint is answering 404 — a server release or config defect. |
| `/readyz` reports `local_cutout` ≠ `enabled` | Includes `emergency_disabled` left on after an incident. |

### Warn — investigate, do not wake anyone

| Condition | Notes |
|---|---|
| `local_accepted / local_attempted` falls **> 20 points** after a release | Engine quality regression, or a threshold changed without benchmark evidence. |
| `cloud_fallback_used` rises **> 20 points** release over release | Same signal from the other side. |
| `health = modelNotInstalled` **> 10 %** more than 48 h after a release | The install-time manifest metadata is not doing its job. |
| `self_test_failure = mask_encoder_lost_alpha` or `cutout_encoder_lost_transparency` | Encoder regression — the exact shape of incidents 2 and 3 above. |
| `self_test_failure = cache_unavailable` | Storage pressure or a sandbox change. |
| `fallback_reason = nativeError` or `timeout` spiking | ML Kit or Vision instability on a particular OS release. |
| A stored cutout without an alpha channel | Backend composition regression — a flattened cutout renders as an opaque rectangle. |
| A cutout rendered with `isCutout = false` | Presentation regression — incident 1. |

### Deliberately NOT alerted

`unsupportedOs` and `missingPlayServices` are properties of the device
population, not defects. Paging on them means paging on the existence of older
iPhones and de-Googled Androids, and an alert that fires on normal conditions is
an alert everyone learns to ignore.

`healthyButImageRejected` is the healthiest possible reason to fall back: the
engine worked and declined one photo. Track the rate; never page on it.

**A production release is not healthy merely because cloud fallback succeeds.**

---

## 4. Emergency switch

### Switching local-first ingestion off

Only during an incident — a provider outage, a storage failure, a bad release
producing unusable masks at scale.

```bash
heroku config:set LOCAL_CUTOUT_EMERGENCY_DISABLE=true -a wtm-api-prod
```

Effect: the endpoint answers **503** (not 404), every device falls back to the
BiRefNet worker, `/readyz` reports `local_cutout=emergency_disabled`, and every
worker logs `AUDIT LOCAL_CUTOUT_EMERGENCY_DISABLE=true` at WARNING on every boot
for as long as it is engaged.

Users are unaffected beyond speed. Nothing is lost; nothing is charged.

### Restoring

```bash
heroku config:set LOCAL_CUTOUT_EMERGENCY_DISABLE=false -a wtm-api-prod
curl -s https://api.wearthemood.com/readyz | python -m json.tool
# expect: "local_cutout": "enabled"
```

Then confirm one real Add Garment on a device and check that `local_attempted`
and `local_accepted` recover in the dashboard.

**This is not a rollout flag.** It must never be left on and forgotten: the alert
on `/readyz` and the per-boot audit log exist precisely because the previous
outage was one config value nobody was watching.

---

## 5. Release verification

```bash
python3 scripts/verify_local_cutout_release.py --target ci                  # every PR
python3 scripts/verify_local_cutout_release.py --target android-production  # local build
python3 scripts/verify_local_cutout_release.py --target ios-production      # ios-release
python3 scripts/verify_local_cutout_release.py --target ios-diagnostic      # internal build
python3 scripts/verify_local_cutout_release.py --target backend --backend-env-file .env.prod
```

Exit code 0 means every applicable invariant holds. Anything else must fail the
build. `--warn-only` reports without failing and is for diagnosis only.

What it asserts beyond gate values: the pinned ML Kit client and its install-time
manifest metadata, `minSdk >= 24`, that every native source is a member of its
build target, that both plugins are registered on the channel Dart actually calls,
that the RunnerTests bundle compiles the same production sources it claims to
test, that the diagnostic export is absent from store builds, that the backend
endpoint exists and is on, and that recorded physical-device evidence still
matches the native code being shipped. With `--artifact` it also proves the
shipped APK/AAB/IPA really contains the compiled engine.

Every guard has a negative test in
`backend/app/tests/test_local_cutout_release_verifier.py` that breaks a copy of
the repository and proves the guard fires. A release gate that has never been seen
to fail is not a gate.

---

## 6. Device evidence

`docs/bg/local_cutout_device_evidence.json` records physical-device sessions.
Entries are keyed by `native_fingerprint` — a hash of the platform's native
sources plus `local_cutout_compatibility.json` — so **any** change to the engine,
the plugin, the registration, the pinned ML Kit client, the Vision revision or the
validated toolchain invalidates prior evidence and forces the matrix again.

```bash
# what fingerprint does the working tree have?
python3 scripts/verify_local_cutout_release.py --print-fingerprint android

# after a device session
python3 scripts/verify_local_cutout_release.py --record-device-evidence android \
  --recorded 2026-08-05 --app-version 1.0.19+22 --runs 6 --result pass \
  --notes "Pixel 7a and Galaxy A54, cold install and update-over, 0 crashes"
```

The fingerprint is computed from the working tree by the script — never supplied
by hand. Never edit one to make a build pass; that converts a real guarantee into
a comment.

**Compilation is not validation. A mocked unit test is not a device.**

### Required matrix

**Android** — API 24 floor, current production Android, current Play services,
model already installed, model initially missing, offline after install, upgrade
over an older production version, process death and cold relaunch, repeated
sequential removals, rapid double tap, low-memory recovery.

**iOS** — iOS 17 (the minimum Vision path), current production iOS, cold install,
update over the previous TestFlight build, repeated operations, cancellation,
timeout followed by another attempt, low-memory and background/foreground
transitions, and the transparent result actually visible in the closet.

---

## 7. Dependency policy

ML Kit Subject Segmentation is a **beta** dependency whose model ships through
Google Play services, and Apple Vision's behaviour is tied to the OS. "It still
builds" is not evidence that either still works.

Pinned in `docs/bg/local_cutout_compatibility.json`. Renovate, Dependabot,
`flutter upgrade`, `gradle --refresh-dependencies` and `pod update` must not move
any of these on their own:

* `com.google.android.gms:play-services-mlkit-subject-segmentation`
* the Play services module-install APIs
* the Vision request revision
* the Flutter engine lifecycle / plugin registration
* the Android and iOS image codecs
* `minSdk` and `IPHONEOS_DEPLOYMENT_TARGET`

This is a **revalidation requirement, not a permanent freeze.** Security updates
are expected — they simply cannot ship as an unvalidated side effect of an
unrelated task. Bump the manifest value together with a fresh device matrix; the
fingerprint change makes the requirement automatic.

---

## 8. Performance

Measured separately so a regression is attributable rather than "it feels slow":
`capability_ms`, `model_prepare_ms`, `decode_ms`, `inference_ms`, `mask_ms`,
`encode_ms`, `native_total_ms`, `local_upload_ms`, `backend_compose_ms`,
`storage_ms`, `api_total_ms`, `cloud_fallback_total_ms`.

Fast-path intent, all of it load-bearing:

* the ML Kit segmenter is created once, never per image;
* neither engine initialises on the UI thread;
* one native operation at a time (a second is refused with `busy`, not queued —
  two concurrent runs on a mid-range device is the shape of an OOM);
* no database connection is held during image, provider or storage work;
* cutout and mask uploads run concurrently (measured 8178 ms → 4728 ms end to end);
* thumbnail CPU work stays off the async event loop;
* the model is neither re-downloaded nor re-initialised per screen;
* the self-test runs at most once per app version — never on launch.

Do not turn a soft warning into a hard rejection without benchmark evidence from
the regression corpus, and never tune a threshold from one or two photos.

---

## 9. Release checklist

A release containing local-cutout changes ships only after all of:

1. Branch reconciled; no earlier work discarded.
2. Production gates verified `true / true / true`.
3. Diagnostics verified `false` for store builds.
4. Backend endpoint verified enabled (`/readyz` → `local_cutout: enabled`).
5. Android native tests pass.
6. Swift native tests **execute** (count asserted) and pass.
7. `flutter analyze`, `dart format --set-exit-if-changed` and `flutter test` pass.
8. Backend `ruff check`, `ruff format --check` and `pytest` pass.
9. Signed APK/AAB inspection passes.
10. Signed IPA/archive inspection passes.
11. A real Android local cutout succeeds on hardware.
12. A real iPhone Apple Vision cutout succeeds on hardware.
13. Both persist through the backend.
14. Both display **transparently** in the closet.
15. Cloud fallback tested intentionally.
16. Analytics confirms local attempts and acceptance.
17. No release-wide channel/gate/backend fallback present.

An internal diagnostic build is **not** production validation. Mocked unit tests
are **not** physical-device validation.
