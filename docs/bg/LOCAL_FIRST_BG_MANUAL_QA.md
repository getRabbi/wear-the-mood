# Local-first background removal — device QA script

**Owner-run.** Nothing in this document has been executed. It exists because the
feature cannot be signed off without hardware: see
`LOCAL_FIRST_BG_TEST_REPORT.md` §2 and §3.

Run it on **at least one Android 24+ device** and **one iOS 17+ device**, record every
result, then paste the completed §12 table into the test report before any gate is
flipped. A blank row is fine. An optimistic row is not.

---

## 1. What you are testing

On-device background removal (Apple Vision on iOS 17+, Google ML Kit Subject
Segmentation on Android 24+) replacing the ~20–60 s wait on the Azure BiRefNet
worker. BiRefNet remains the **only** automatic fallback and is never removed.

Ship state: **five gates, all OFF.** This script turns them on **for a local test
build only** — never in `app/env/prod.json`, never on Heroku.

---

## 2. Prerequisites

* Android: a physical device on **API 24+** with Google Play services current, USB
  debugging on. An emulator can work but Play-services model delivery is less
  reliable there; a physical device is the real test.
* iOS: a physical device on **iOS 17.0+**. A simulator is **not** acceptable —
  `VNGenerateForegroundInstanceMaskRequest` is unreliable there, so a green
  simulator run is not evidence.
* A staging or dev backend you are willing to write rows to. **Do not point this at
  production.**
* `adb` at `E:/SDK/platform-tools` for Android logs.

> The installed store build has a different signature. `adb uninstall
> com.fashionos.app` first, or the install fails with a signature mismatch.

---

## 3. Build a gated test build

Do **not** add these keys to `app/env/prod.json`. Pass them on the command line so
the change lives only in this build.

### Android

```powershell
cd E:\dopplefit\app
flutter build apk --debug `
  --dart-define-from-file=env/dev.json `
  --dart-define=LOCAL_BG_REMOVAL_ENABLED=true `
  --dart-define=LOCAL_BG_ANDROID_ENABLED=true
```

### iOS

```bash
flutter build ios --debug --no-codesign \
  --dart-define-from-file=env/dev.json \
  --dart-define=LOCAL_BG_REMOVAL_ENABLED=true \
  --dart-define=LOCAL_BG_IOS_ENABLED=true
```

### Backend (staging only)

```bash
LOCAL_CUTOUT_UPLOAD_ENABLED=true
LOCAL_CUTOUT_IMPROVE_ENABLED=true
STORAGE_WRITES=r2          # required — else the endpoint 503s and the app falls back
```

**Both sides must be on.** With only the Dart gates on, the app correctly falls back
to the cloud path — which is itself worth confirming (test 4.1).

---

## 4. Gate behaviour

| # | Step | Expected |
|---|---|---|
| 4.1 | Dart gates ON, backend gate **OFF**. Add a garment. | Local attempt runs, endpoint 404s, app silently falls back to `POST /v1/wardrobe` → BiRefNet. Item still lands correctly. **No error shown to the user.** |
| 4.2 | Both sides ON. Add a garment. | Local path used; see §5. |
| 4.3 | Dart gates **OFF** (plain `flutter build apk --debug`). Add a garment. | Identical to today's shipped behaviour. No native call at all — confirm with `adb logcat -s WtmBackgroundRemoval` staying silent. |
| 4.4 | iOS 15.5 or 16.x device, gates ON. | Reports `unsupported_os`, uses cloud path, no crash. **Skip if no such device** — record as skipped, not passed. |

---

## 5. Android — ML Kit local segmentation

| # | Step | Expected | Record |
|---|---|---|---|
| 5.1 | First launch after install, add a garment. | Play services downloads the segmentation model. **First run may be slower or fail with a typed `model_unavailable`** → cloud fallback, no crash. | first-run outcome |
| 5.2 | Add a garment again (model now cached). | Cutout preview appears **without** the "removing background" wait. | preview latency |
| 5.3 | `adb logcat` during 5.2. | Stage timings only. **No path, filename, object key or URL in any log line.** | pass/fail |
| 5.4 | Plain garment, plain background. | Clean edges, garment fully retained. | quality 1–5 |
| 5.5 | Garment with lace / fringe / thin straps. | Note where edges break. ML Kit is a *subject* segmenter, not a matting model — soft detail is its known weakness. | quality 1–5 |
| 5.6 | Garment held in hand / worn. | Note whether hands/body are included as subject. This is the expected failure mode to watch. | quality 1–5 |
| 5.7 | Busy/cluttered background. | Either a good cutout or a quality **rejection** → cloud fallback. Never a mangled cutout saved as final. | pass/fail |
| 5.8 | Photo with no clear subject (e.g. a wall). | Hard-rejected on area bounds → cloud fallback. | pass/fail |

---

## 6. iOS — Apple Vision local segmentation

Same matrix as §5, plus:

| # | Step | Expected | Record |
|---|---|---|---|
| 6.1 | iOS 17+ device, add a garment. | Vision runs on-device; no model download needed. | latency |
| 6.2 | Multi-instance photo (two garments in frame). | `allInstances` handled; subject count bucketed. The correct instance mask is used — **not** the raw `instanceMask`, which is a label map (0 = background), never alpha. | pass/fail |
| 6.3 | Console log during 6.1. | `decode_ms`, `inference_ms`, `mask_ms`, `composite_ms`, `write_ms` and a bounded error code only. No paths. | pass/fail |
| 6.4 | Repeat 6.1 ten times in a row. | No memory growth, no pixel-buffer crash. Watch Xcode's memory gauge. | peak MB |

---

## 7. Local preview timing & UI responsiveness

| # | Step | Expected | Record |
|---|---|---|---|
| 7.1 | Time from tapping Confirm to the cutout preview being visible. | Target: **noticeably faster than the BiRefNet path** (baseline 12.2 s inference + up to 46.7 s cold model init). | ms |
| 7.2 | During segmentation, scroll / tap around the screen. | UI stays responsive; no dropped-frame jank, no ANR. Segmentation must not run on the platform thread. | pass/fail |
| 7.3 | Rotate the device mid-segmentation. | No crash, no duplicate attempt. | pass/fail |
| 7.4 | Add 5 garments back to back. | Each completes; no leaked temp files (check §10). | pass/fail |

---

## 8. BiRefNet fallback

| # | Step | Expected |
|---|---|---|
| 8.1 | Airplane mode **on**, add a garment. | Local segmentation still runs (it is on-device), upload fails, normal offline error. No corrupt item. |
| 8.2 | Force a low-quality local result (test 5.8). | Hard-rejected → `POST /v1/wardrobe` with the **same object key** — the photo is **not** re-uploaded. Verify only one upload in the backend log. |
| 8.3 | Backend gate off mid-session. | Next add falls back cleanly. |
| 8.4 | Kill the app during segmentation, reopen. | No half-created item; no orphaned row. |

---

## 9. `sourceMissing` re-upload flow

| # | Step | Expected |
|---|---|---|
| 9.1 | Delete the uploaded original from R2 **before** the local-cutout POST lands (staging only). | Backend returns `SOURCE_MISSING` (422). App asks the user to **pick the photo again** — it does **not** silently fall back to the cloud path, because the worker would read the same missing object and fail too. |
| 9.2 | Re-pick the photo when prompted. | Fresh upload, fresh key, succeeds. |
| 9.3 | Simulate a transient storage read failure instead. | `PROVIDER_ERROR` (503) — retryable, **not** a reselect prompt. |
| 9.4 | Inspect both responses. | Neither carries an object key or a signed URL. |

---

## 10. Cancellation, retry, disposal, cache cleanup

| # | Step | Expected |
|---|---|---|
| 10.1 | Start an add, then immediately hit back. | Operation cancelled by **operation id**; scratch directory removed. |
| 10.2 | Start an add, background the app, return. | No duplicate result; no stale preview. |
| 10.3 | Tap Confirm twice quickly. | One attempt, one item. No duplicate ledger row, no duplicate signal. |
| 10.4 | Inspect `<app cache>/wtm-local-cutout/`. | One directory per live operation, named by operation id, removed on completion or cancellation. Directories older than **6 h** are swept. |
| 10.5 | Verify no delete call ever receives a path from the native channel. | Cleanup is operation-id-only by contract — confirm no stray files outside the app-owned cache root. |

---

## 11. Improve edges / Fix cutout / regression

These are **two separate free features with separate gates** — do not conflate them.

| # | Step | Expected |
|---|---|---|
| 11.1 | Open a garment with a cutout. Tap **Improve edges**. | Server re-runs the AUTOMATIC cutout. The **current cutout stays visible throughout**. |
| 11.2 | Force the worker to fail the improvement. | The **previous cutout survives** — `cutout_url`, `thumbnail_url` and every `media_assets` row untouched. |
| 11.3 | Tap **Improve edges** twice quickly. | Server-side no-op; no duplicate attempt, no duplicate signal. |
| 11.4 | Check credits before/after. | **Unchanged.** Improve edges is free. |
| 11.5 | Tap **Fix cutout** (`CUTOUT_EDITOR_ENABLED`, already live). | Manual Erase/Restore editor opens, unchanged by this work. |
| 11.6 | **AI Enhance** on a locally-created item. | Behaves exactly as on a cloud-created item. Costs the same. |
| 11.7 | Closet grid, offline cache, delete item. | Unchanged. Deleting sweeps the `cutout_mask` object with the rest. |
| 11.8 | Try-on with a locally-created garment. | Works identically — try-on reads `cutout_url`, which is populated either way. |
| 11.9 | Account deletion. | Removes every `media_assets` role including `cutout_mask`. |

---

## 12. Result table — paste into the test report

```text
Device / OS:
Engine:                     ML Kit 16.0.0-beta1 | Apple Vision
App build:                  1.0.15+18, debug, gates on via --dart-define
Backend:                    staging, LOCAL_CUTOUT_UPLOAD_ENABLED=true

§4  gate behaviour          PASS / FAIL / SKIPPED   notes:
§5  Android segmentation    PASS / FAIL / SKIPPED   notes:
§6  iOS segmentation        PASS / FAIL / SKIPPED   notes:
§7  preview timing          ______ ms to visible    UI responsive: Y / N
§8  BiRefNet fallback       PASS / FAIL / SKIPPED   notes:
§9  sourceMissing           PASS / FAIL / SKIPPED   notes:
§10 cancel/cleanup          PASS / FAIL / SKIPPED   notes:
§11 improve/fix/regression  PASS / FAIL / SKIPPED   notes:

Cutout quality 1-5:  plain ___  soft-detail ___  worn ___  cluttered ___
Prepare ms ___   Inference ms ___   Preview visible ms ___   Peak MB ___

Verdict:  activation-ready / not ready
Blockers found:
```

---

## 13. After QA — put it back

1. Rebuild **without** the `LOCAL_BG_*` defines and confirm the app behaves exactly as
   the shipped build.
2. Unset `LOCAL_CUTOUT_UPLOAD_ENABLED` and `LOCAL_CUTOUT_IMPROVE_ENABLED` on staging.
3. Confirm production still has neither set: `heroku config -a wtm-api-prod --json`.
4. Paste §12 into `LOCAL_FIRST_BG_TEST_REPORT.md` §7.1 and §4.2.

Rollback, if a gate was ever flipped in production, is in
`BIREFNET_CUTOUT_RUNBOOK.md` → *Rollback — local-first background removal*.
