# Local-first background removal — controlled rollout runbook

**Nothing in this document has been executed.** Every command is a placeholder for a
human to run, in order, with a decision point between each stage. No step here was
performed while writing it, and no gate was flipped.

Read alongside:

* `LOCAL_FIRST_BG_TEST_REPORT.md` — what is and is not validated
* `LOCAL_FIRST_BG_MANUAL_QA.md` — the device script that gates stages 5 and 7
* `BIREFNET_CUTOUT_RUNBOOK.md` — rollback, and the existing cloud cutout path

---

## 0. The seven statements that govern this rollout

1. **The branch may be merged dormant.** `feat/local-first-background-removal` is safe
   to merge and safe to deploy as-is. All five gates default OFF, both new endpoints
   404 while their gate is off, and every pre-existing suite passes unchanged. Merging
   changes no user-visible behaviour.
2. **Android is device-validated; iOS is not.** As of 2026-07-29 Android completed 31
   consecutive device runs with 0 SIGSEGV, 9 distinct images visually checked, a median
   local completion of ~2.6 s, successful `local-cutout` ingestion with items born
   `cutout_status=done`, and no BiRefNet job on a valid local result. **iOS has never
   run local inference.** Full detail: `LOCAL_FIRST_BG_TEST_REPORT.md` §0.
3. **Local inference still stays OFF until you decide to roll it out.** Device
   validation is not the same as an activation decision; nothing here flips a gate.
4. **Android and iOS are enabled independently.** The arms are separate flags for
   exactly this reason. Never both in the same release. iOS additionally still needs its
   own device QA before it may be enabled at all.
5. **The 74 Swift XCTest functions remain unexecuted** — the `RunnerTests` target is
   not configured for an arm64 simulator (pre-existing Flutter-template limitation).
   iOS mask maths, `instanceMask` label-map handling and pixel-buffer safety are
   verified by review and compilation only. Decide this consciously before iOS
   activation; options are in `LOCAL_FIRST_BG_IMPLEMENTATION_PLAN.md` §8c.
6. **A native SIGSEGV inside ML Kit is NOT recoverable.** Typed failures — NaN,
   infinity, a value outside the `[-0.25, 1.25]` safety range, a bad mask length or
   bounds, no subject, a coverage extreme — all degrade cleanly to Azure BiRefNet. A
   crash inside the SDK's own `.so` kills the process instead, and no Kotlin or Dart
   handler can catch it. Accept that risk explicitly before enabling Android.
7. **Rollback disables the backend master gate first.** It is server-side, instant, and
   needs no app release — already-shipped builds fall back to the Azure BiRefNet path
   on their own. App-side flags are the follow-up, never the first response.

---

## 1. Gate reference

| Gate | Layer | Where | Default |
|---|---|---|---|
| `LOCAL_CUTOUT_UPLOAD_ENABLED` | backend | Heroku config var | `false` |
| `LOCAL_CUTOUT_IMPROVE_ENABLED` | backend | Heroku config var | `false` |
| `LOCAL_BG_REMOVAL_ENABLED` | app | `--dart-define` at build | `false` |
| `LOCAL_BG_ANDROID_ENABLED` | app | `--dart-define` at build | `false` |
| `LOCAL_BG_IOS_ENABLED` | app | `--dart-define` at build | `false` |

Backend gates are **runtime** — flip without a release. App gates are **compile-time** —
changing one needs a new build. That asymmetry is deliberate: the fast lever is
server-side.

`CUTOUT_EDITOR_ENABLED` is **not** part of this rollout. It is the pre-existing Fix
cutout editor, live in production since Heroku v14 (2026-07-23). Leave it alone.

---

## 2. Merge the branch (dormant)

```bash
# Placeholder — human runs this.
git checkout migration/heroku-azure
git merge --no-ff feat/local-first-background-removal
git push origin migration/heroku-azure
```

Expected: no behaviour change anywhere. Confirm before continuing:

```bash
grep -rn "defaultValue: false" app/lib/core/config/feature_gates.dart   # 4 gates, all false
grep -in "LOCAL_BG\|LOCAL_CUTOUT" app/env/prod.json                     # must return nothing
```

---

## 3. Stage 1 — deploy backend code with the local endpoint gate OFF

Production release is manual and gated by the protected `production` GitHub
Environment (requires a reviewer). Nothing auto-deploys on push.

```bash
# Placeholder — human runs this from the GitHub UI or CLI.
gh workflow run migration-deploy.yml -f target=prod
# then approve the `production` environment when prompted
```

Do **not** set any new config var in this stage.

### Verify health and old-app compatibility

```bash
curl -s https://api.wearthemood.com/readyz            # GIT_SHA should be the merged commit
heroku config -a wtm-api-prod --json | grep -i LOCAL_CUTOUT   # expect NO output
```

Then, on a device running the **currently published** store build (not a new build):

| Check | Expected |
|---|---|
| Add a garment | Unchanged: upload → `POST /v1/wardrobe` → BiRefNet → poll → reveal |
| Fix cutout | Still works (its own gate, untouched) |
| AI Enhance, try-on, closet, delete | Unchanged |

**Stop here if anything differs.** A dormant deploy that changes behaviour means a gate
leaked, and no further stage should proceed.

---

## 4. Stage 2 — enable the backend gate in staging only

```bash
# Placeholder — human runs this. STAGING ONLY.
heroku config:set LOCAL_CUTOUT_UPLOAD_ENABLED=true  -a wtm-api-staging
heroku config:set LOCAL_CUTOUT_IMPROVE_ENABLED=true -a wtm-api-staging
heroku config -a wtm-api-staging --json | grep -i LOCAL_CUTOUT
```

`STORAGE_WRITES=r2` must already be set on staging — without private R2 writes the
endpoint returns 503 and the app falls back to the cloud path, which would make the
whole test vacuous. Confirm it:

```bash
heroku config:get STORAGE_WRITES -a wtm-api-staging     # expect: r2
```

Production stays untouched in this stage. Verify:

```bash
heroku config -a wtm-api-prod --json | grep -i LOCAL_CUTOUT   # still NO output
```

---

## 5. Stage 3 — internal Android build (master ON, Android ON, iOS OFF)

```powershell
# Placeholder — human runs this. Points at STAGING.
cd E:\dopplefit\app
flutter build apk --debug `
  --dart-define-from-file=env/dev.json `
  --dart-define=LOCAL_BG_REMOVAL_ENABLED=true `
  --dart-define=LOCAL_BG_ANDROID_ENABLED=true
```

`LOCAL_BG_IOS_ENABLED` is simply omitted — it defaults to `false`. Do not pass it as
`false`; omitting is the same thing and leaves less to misread.

This is an **internal** build. Not signed for release, not uploaded, not a Play track.

---

## 6. Stage 4 — test the Android matrix

Run **all** of `LOCAL_FIRST_BG_MANUAL_QA.md` §4, §5, §7, §8, §9, §10, §11 on a
physical Android device on API 24+ with current Play services.

Record in the QA §12 table and paste into `LOCAL_FIRST_BG_TEST_REPORT.md` §7.1.

**Gate:** do not proceed to iOS until the Android matrix is complete and its results are
written down. Specifically confirm:

* Play-services model delivery on a cold first run, including its failure path
* a hard-rejected result falls back to BiRefNet **reusing the same object key** — the
  photo is not re-uploaded
* `SOURCE_MISSING` prompts a reselect and does **not** silently queue a doomed item
* Improve edges never removes a valid cutout, and spends no credits
* logs carry no path, filename, object key or URL

---

## 7. Stage 5 — TestFlight build (master ON, iOS ON, Android arm unaffected)

**Blocked** until the Apple Developer account is active — no APNs key, no ASC key, no
TestFlight, so an iOS build cannot currently be installed on a device at all. See
`docs/IOS_APPSTORE_READINESS.md`.

```bash
# Placeholder — human runs this once Apple credentials exist.
flutter build ios --release \
  --dart-define-from-file=env/staging.json \
  --dart-define=LOCAL_BG_REMOVAL_ENABLED=true \
  --dart-define=LOCAL_BG_IOS_ENABLED=true
```

Before this stage, settle statement 4 of §0: either fix the `RunnerTests` arm64
configuration and actually run the 74 Swift tests, or record an explicit written
acceptance that iOS ships with them unexecuted.

---

## 8. Stage 6 — test the iOS matrix

Run `LOCAL_FIRST_BG_MANUAL_QA.md` §4, §6, §7, §8, §9, §10, §11 on a physical iOS 17+
device. A simulator is not acceptable — `VNGenerateForegroundInstanceMaskRequest` is
unreliable there, so a green simulator run is not evidence.

Additionally confirm on iOS specifically:

* multi-instance photos pick the correct instance mask, not the raw `instanceMask`
  label map
* ten consecutive runs show no memory growth and no pixel-buffer crash
* an iOS 15.5/16.x device reports `unsupported_os` and uses the cloud path — or record
  it as **skipped** if no such device is available

---

## 9. Stage 7 — real-image QA set

Assemble a fixed set of **at least 30** real garment photos and keep it for every
future change, so results are comparable over time. Cover: plain background, cluttered
background, lace/fringe/thin straps, garment worn on a body, garment held in hand, dark
garment on dark background, white on white, patterned, reflective/satin, and at least
three phone cameras.

Run the same set through **both** engines and the BiRefNet path. Record per image:
accepted or rejected, which fallback reason if rejected, and a 1–5 quality score.

---

## 10. Stage 8 — compare acceptance and fallback rates

From the §9 set, compute per platform:

| Metric | Meaning | Suggested go/no-go |
|---|---|---|
| local acceptance rate | share of images the quality policy accepts | high enough that most users see the fast path |
| hard-rejection rate | share falling back to BiRefNet | a high rate is not a bug — it is the safety net working |
| soft-warning rate | accepted but flagged | informs threshold tuning |
| median time to visible preview | vs the BiRefNet baseline (12.2 s inference, up to 46.7 s cold init) | must be clearly faster or the feature has no point |
| quality score vs BiRefNet | side by side | local must not be visibly worse on the common case |

**Only now** may the thresholds in `local_cutout_quality_policy.dart` be tuned, using
these measurements. They were deliberately left at their conservative shipped values
rather than fitted to invented numbers. Only `minForegroundAreaRatio` (0.01) and
`maxForegroundAreaRatio` (0.995) can reject; every other threshold merely warns.

---

## 11. Stage 9 — production activation (requires explicit human approval)

Do not run this until stages 3–8 are complete for the platform being enabled and the
results are recorded in the test report.

**One platform at a time.** Backend gate first, then that platform's store build.

```bash
# Placeholder — human runs this, after written approval.
heroku config:set LOCAL_CUTOUT_UPLOAD_ENABLED=true -a wtm-api-prod
# Improve edges is a separate decision; enable it on its own schedule:
heroku config:set LOCAL_CUTOUT_IMPROVE_ENABLED=true -a wtm-api-prod
```

With the backend gate on and **no** store build carrying the app flags, nothing changes
for users — every shipped build still uses the cloud path. That is the intended safe
intermediate state: the endpoint can be live and idle before any client uses it.

Then the store build for the QA-passed platform only:

```powershell
# Placeholder — Android. Version bump is a separate human decision.
flutter build appbundle --release `
  --dart-define-from-file=env/prod.json `
  --dart-define=LOCAL_BG_REMOVAL_ENABLED=true `
  --dart-define=LOCAL_BG_ANDROID_ENABLED=true
```

Prefer a **staged Play rollout** (e.g. 10% → 50% → 100%) and watch the analytics in §12
between steps. Repeat separately for iOS once its QA is done — never in the same
release.

### Before any release build, re-check

* ML Kit Subject Segmentation is still `16.0.0-beta1` — look for a stable release first
* `minSdk` 24 drops Android 6.0 devices; this takes effect on the next store build
  whether or not the gates are on
* the version bump is a deliberate, separate decision

---

## 12. What to watch after activation

| Signal | Source | Act if |
|---|---|---|
| `local_bg_hard_rejected` / `local_bg_succeeded` | PostHog | rejection rate far above the QA baseline → thresholds or engine regression |
| `local_bg_fallback_started` | PostHog | rising → local path failing in the field; BiRefNet load climbing |
| `local_bg_source_missing` | PostHog | any sustained volume → upload/storage problem, not a segmentation problem |
| `local_bg_succeeded` latency bucket | PostHog | drifting into `gt15s` → local is no longer a speed win |
| Azure `wtm-rembg-job` invocations | Azure | should **fall** as local adoption rises; a rise means fallback is dominating |
| Sentry | Sentry | any native crash in `BackgroundRemoval` / `background` → roll back immediately |

All events are bucketed and carry no path, object key, URL, exact dimension or raw
exception text.

---

## 13. Rollback

**Step 1 — always first. Server-side, instant, no release:**

```bash
heroku config:unset LOCAL_CUTOUT_UPLOAD_ENABLED  -a wtm-api-prod
heroku config:unset LOCAL_CUTOUT_IMPROVE_ENABLED -a wtm-api-prod
```

Both endpoints return 404 again. Already-shipped builds with the app flags on treat
that as a recoverable failure and fall back to `POST /v1/wardrobe` → Azure BiRefNet.
Items already created locally are ordinary items and stay valid.

**Step 2 — only if a specific engine is at fault.** Rebuild omitting that platform's
flag and ship. Android and iOS roll back independently.

**Not required:** no migration to revert, no `media_assets` cleanup (item and account
deletion already sweep `cutout_mask`), no worker or image change (the Azure worker is
untouched by this feature), no credit or ledger repair (the local path spends no
credits and Improve edges is free).

**For an individual bad cutout,** the product already has the recovery: Improve edges
re-runs BiRefNet server-side, Fix cutout opens the manual editor. Neither removes a
valid cutout, and a failed improvement preserves the previous one — so no operator
intervention is needed.

Full detail: `BIREFNET_CUTOUT_RUNBOOK.md` → *Rollback — local-first background
removal*.

---

## 14. Final stop gate

Stages 3 onward require explicit human release authorization each time. Nothing in this
runbook may be automated, and no store artifact may be built or uploaded without a
deliberate human decision.
