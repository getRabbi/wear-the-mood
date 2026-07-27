# Local-first background removal — implementation plan (Phase 0 audit)

> **Read-only audit.** This document changes no runtime behaviour. It records the
> repository's *actual* current state, the target design, and the risks, so every
> later phase can be reviewed against a written contract instead of guesswork.
>
> Companion documents: `BIREFNET_CUTOUT_RUNBOOK.md` (the cloud path that stays the
> fallback), `../migration/MIGRATION_STATE.md` (real production topology).

| Field | Value |
|---|---|
| Audit date | 2026-07-27 |
| Branch | `feat/local-first-background-removal` |
| Base SHA | `7237347ada4de13bd65d87500ae8cefb93bb2c42` (`migration/heroku-azure`) |
| `origin/main` at audit time | `7ed086e9a303f3fc5679942dbaaf06ebb45f5981` — **contained in the base** |
| Latest migration | `0048_restore_new_user_trigger.sql` → next free number is **0049** |
| Backend tests | `699 passed, 1 warning` (`backend/.venv` + `python -m pytest -q`, 170 s) |
| Flutter tests | `632 passed` (`flutter test`) |
| Flutter analyze | `No issues found!` |

## ⚠ Deviation from the prompt's branch instruction (needs acknowledgement)

The prompt says to branch from `origin/main`. This branch was instead cut from
`migration/heroku-azure` (`7237347`), which **contains all of `origin/main`** plus
four commits that are not yet merged there:

| Commit | Why it matters here |
|---|---|
| `7237347` fix(cutout): enable Fix Cutout consistently on iOS builds | Adds `app/lib/ui/closet/wtm_cutout_gate.dart` — `cutoutEditorEnabledProvider` + `canFixCutout()`, the exact rule §9.4 must reuse for the "Fix cutout" button |
| `441312f` fix(ui): stop previous page bleeding through iOS transitions | Touches `wtm_scaffold.dart` / router transitions that the Add Garment screen renders inside |
| `9fd9f15`, `ed5e371` docs(migration) | Phase 7 DigitalOcean decommission records |

Branching from `origin/main` would have started from a tree without
`wtm_cutout_gate.dart`, so Phase 5/6 would either duplicate that rule or conflict
with it on merge. Nothing was rebased, force-pushed, or discarded. Say the word
and the branch can be re-cut from `origin/main` before Phase 1 — but the
recommendation is to keep the current base.

Also present and deliberately untouched (untracked, not committed): the two
prompt `.md` files at the repo root and `app/env/prod.json.bak-2026072*` (the
owner's own env backups).

---

## 1. Current state

### 1.1 Production topology (authoritative — `MIGRATION_STATE.md`, not `CLAUDE.md` §2)

`CLAUDE.md` §2 still describes a DigitalOcean droplet as the backend host. **That
is stale.** Since the 2026-07-20 cutover:

- **API** — Heroku `wtm-api-prod` (Basic ×1, container stack, US).
- **Workers** — Azure Container Apps **Jobs**, event-triggered by KEDA on Azure
  Storage Queue depth. `wtm-rembg-job` = the cutout worker, **4 vCPU / 8 GiB**,
  `maxExecutions 1`, scale-to-zero, BiRefNet General Lite baked into the image.
- **DB** — Supabase US `ghzabbceoaoertatkjyg`.
- **Media** — Cloudflare R2 (`STORAGE_WRITES=r2` on both the API and the worker).
- **Recovery** — Azure Job `wtm-prod-recovery`, every 5 min.
- **DigitalOcean** — decommissioned in place; containers stopped. **No longer a
  rollback path.** `docker-compose.yml` and `app.workers.bg_worker.run_once` /
  `requeue_stale` are legacy code paths that nothing runs today.

### 1.2 Current Add Garment flow (the live WTM path)

`app/lib/ui/closet/wtm_add_garment_screen.dart`, states
`capture → processing → confirm | failed`:

```text
_pick(source)
  └─ WardrobeImageService.pickAndCompress(source)
        image_picker maxWidth/maxHeight 1600, imageQuality 90
        → FlutterImageCompress.compressWithList(minWidth/minHeight 1600,
            quality 80, JPEG, keepExif: false)      ← the EXACT bytes we must reuse
_run()
  ├─ WardrobeImageService.upload(bytes)
  │     R2 gate ON  → POST /v1/media/upload-url (sector "wardrobe")
  │                   → presigned PUT straight to R2 → MediaRef(objectKey)
  │     gate OFF    → legacy Supabase `wardrobe` bucket → MediaRef(legacyUrl)
  ├─ WardrobeRepository.addItem(imageUrl:, objectKey:)  → POST /v1/wardrobe (201)
  │     server: insert row, cutout_status='queued', insert_asset(role='original'),
  │             commit, THEN enqueue_signal(KIND_REMBG) → stamp cutout_last_signal_at
  ├─ [optional] AI Enhance job kicked off (credits, unchanged by this project)
  ├─ _pollUntilCutoutReady(id)   first 350 ms, then every 800 ms, TIMEOUT 200 s
  │     polls GET /v1/wardrobe until !isProcessingCutout
  │     fake staged copy by elapsed time: warming <12 s, clearing <40 s,
  │       refining <70 s, almost ≥70 s + a tip rotating every 8 s
  └─ _refreshAndFind(id) → confirm stage (name + category chips → PATCH)
```

Confirm stage buttons: **Save**, post-hoc **AI Enhance** (subscriber), and **Fix
cutout** when `canFixCutout(item, enabled: cutoutEditorEnabledProvider)` —
i.e. the compile-time gate is on **and** `item.cutoutUrl != null`.

A second, older flow exists at `app/lib/features/wardrobe/add_wardrobe_item_screen.dart`
+ `wardrobe_add_processing.dart` (reachable only under `--dart-define=WTM_SHELL=false`;
`WTM_SHELL` defaults **true**, so it is dead in every shipped build). **Out of scope** —
it must keep compiling and keep its tests green, nothing more.

### 1.3 R2 presign → object key → media ledger

```text
POST /v1/media/upload-url {sector,content_type,byte_size}
  ├─ 503 PROVIDER_ERROR when !r2_writes_enabled  (app falls back to legacy upload)
  ├─ sector table decides visibility SERVER-SIDE:
  │     "wardrobe" → private, owner_kind=wardrobe_item, role=original
  ├─ allow-list image/jpeg|png|webp, max 12 MB
  └─ object_key = f"{user.id}/{sector}/{uuid4().hex}{ext}"   ← random + user-scoped
POST /v1/wardrobe {object_key}
  └─ insert_asset(owner_kind='wardrobe_item', role='original', visibility='private',
                  storage_provider='r2', object_key=…)
```

`media_assets` (migration `0021`): polymorphic `(owner_kind, owner_id, role)`, no
FKs (it is the deletion ledger), RLS select-only for clients, **service-role
writes only**. Indexes: `(owner_kind, owner_id, role)`, `(user_id)`, partial
legacy index. **No unique constraint on `object_key` and no unique constraint on
`(owner_kind, owner_id, role)`** — uniqueness of the active row is maintained
*procedurally* by `_replace_role_asset()`, which locks every active row of that
role `for update`, updates the oldest in place, and soft-deletes the rest.

Reads: `resolve_images()` batch-signs private R2 keys; `_with_media()` overlays
`image_url` / `cutout_url` / `thumbnail_url` onto `WardrobeItemResponse`.

### 1.4 Cutout worker + claim/recovery semantics

```text
API commit → enqueue_signal(KIND_REMBG, item_id)  [best-effort; False on failure]
             on success only: cutout_last_signal_at = now()
KEDA sees queue depth → wtm-rembg-job execution
  rembg_worker.handle_signal:
    claim_cutout(item_id, stale_seconds=WORKER_STALE_SECONDS)   ← claim.py
      claimable when cutout_status='queued'
                 OR ('processing' AND cutout_locked_at IS NULL
                     OR cutout_locked_at < now() - stale)
      sets cutout_status='processing', cutout_locked_at=now(),
           attempt_count = attempt_count + 1
    delete_signal (always, claimed or not)
    if attempt_count > max_attempts → cutout_status='failed',
                                      cutout_error_code='max_attempts'
    process_cutout(conn, row)                                   ← bg_worker.py
      resolve_images(original) → download_image → remover.remove(bytes)
      rembg v2: normalize_source_image → mask-only inference (soft alpha kept)
                → compose_cutout_png → encode_mask_png
      R2: provider.put(cutout, private, prefix "{uid}/cutout", make_thumbnail=True)
          provider.put(mask,   private, prefix "{uid}/cutout-mask", no thumb)
          replace_cutout_assets(...)   ← lock item, swap cutout + cutout_mask
                                          rows, mark done, commit, THEN delete
                                          displaced objects (best-effort)
      on ANY exception → _mark_failed(): cutout_status='failed'
                         (cutout_url and media_assets rows are NOT cleared)
    on success → enqueue_signal(KIND_ENRICHMENT) → orchestrator tags + embeds
wtm-prod-recovery every 5 min (app/tasks/recovery.py):
  stale 'processing'  (cutout_locked_at NULL or older than stale) → re-signal
  stranded 'queued'   (cutout_last_signal_at NULL or stale)       → re-signal
  attempt_count >= max_attempts → 'failed' + cutout_error_code='max_attempts'
```

Migration `0046` gave cutouts a dedicated `cutout_locked_at` lease precisely
because leasing on `updated_at` livelocked (the re-signal fires
`trg_wardrobe_items_updated_at` and reset its own staleness clock). **Any new code
must keep writing `cutout_locked_at` only from the claim.**

### 1.5 What happens to a valid existing cutout during queued/processing

Audited, because §9.5 and §6.4 depend on it:

- `cutout_url`, `thumbnail_url` and the `cutout` / `cutout_mask` `media_assets`
  rows are **only** touched by `replace_cutout_assets()`, which runs *after* the
  new objects are uploaded and swaps them atomically. Re-queuing an item does not
  clear anything.
- `WardrobeItem.displayImageUrl = coverImageUrl ?? thumbnailUrl ?? cutoutUrl ?? imageUrl`
  — independent of `cutoutStatus`. So an item re-queued for improvement keeps
  rendering its current cutout everywhere in the closet.
- `isProcessingCutout` is `cutoutStatus in ('queued','processing')` and is used
  **only** by the two add-flow pollers, not by the closet card. Confirmed by
  grep: the only reads are `wtm_add_garment_screen.dart:318` and
  `wardrobe_add_processing.dart:251`.
- On worker failure `_mark_failed()` sets `cutout_status='failed'` and leaves
  `cutout_url` intact → the old cutout still displays. **Good news for §6.4: no
  refactor of the failure path is required to preserve the previous cutout.** The
  one visible consequence is `cutout_error_code`/`failed` state on an item that
  actually has a fine cutout; Phase 6 will suppress that in the UI rather than
  change worker semantics.
- `canFixCutout()` keys off `cutoutUrl != null`, so "Fix cutout" also survives.

### 1.6 Flags in force today

| Flag | Where | Default in repo | Production |
|---|---|---|---|
| `BG_MODEL` | backend `Settings.background_model`, `SUPPORTED_BG_MODELS = {u2net, u2netp, birefnet-general-lite}` | `u2net` | `birefnet-general-lite` (also baked as `REMBG_MODEL` in the image) |
| `BG_MASK_PIPELINE_V2` | backend | `false` | `true` |
| `CUTOUT_EDITOR_ENABLED` | backend env **and** Dart `--dart-define` | `false` / `false` | backend `true`; Dart default `true` via `codemagic.yaml` `write_prod_env` and `app/env/prod.json.example` |
| `BG_MASK_UPLOAD_MAX_BYTES` | backend | `4_000_000` | 4 MB |
| `BG_MAX_IMAGE_EDGE` | backend | `4096` | 4096 |
| `STORAGE_WRITES` | backend | `legacy` | `r2` |

### 1.7 Native platform state

- **Android** `minSdk = maxOf(flutter.minSdkVersion, 23)`, `namespace`/`applicationId`
  `com.fashionos.app`, Java/Kotlin 17, **R8 minify + resource shrink OFF** (removing
  them broke WorkManager once — do not re-enable). `MainActivity.kt` registers three
  MethodChannels (`wtm/install_referrer`, `wtm/app_links`,
  `com.fashionos.app/notif_settings`) and creates five notification channels.
  Manifest has **no** `com.google.mlkit.vision.DEPENDENCIES` meta-data yet.
  `flutter_launcher_icons.min_sdk_android: 23` mirrors the Gradle floor.
- **iOS** deployment target **15.5** (Podfile + a `post_install` hook that forces
  every pod to 15.5), `use_frameworks!`, `EXCLUDED_ARCHS[iphoneos]=armv7`, bundle id
  `com.wearthemood.app`. `AppDelegate.swift` is 16 lines and uses the new
  `FlutterImplicitEngineDelegate` /
  `didInitializeImplicitFlutterEngine(_:)` → `GeneratedPluginRegistrant.register`.
- ML Kit is **already** a shipped dependency family (`google_mlkit_pose_detection`
  0.14.1, and 15.5 is the iOS floor *because* of it), so adding a second ML Kit
  artifact is not a new licensing or platform decision — see §6 below.

### 1.8 Verified upstream API signatures (checked against official docs, 2026-07-27)

**Google — ML Kit Subject Segmentation (Android)**

- Artifact: `com.google.android.gms:play-services-mlkit-subject-segmentation:16.0.0-beta1`
  (Play-services–delivered, model downloaded by Google Play services).
  ⚠ Still labelled **beta1** by Google. Re-confirm the newest compatible version at
  the start of Phase 3 and pin it explicitly.
- **Requires `minSdkVersion` 24** — this is the sole reason for the 23 → 24 bump.
- Install-time metadata:
  `<meta-data android:name="com.google.mlkit.vision.DEPENDENCIES" android:value="subject_segment" />`
- Options: `SubjectSegmenterOptions.Builder().enableForegroundConfidenceMask()`,
  `.enableForegroundBitmap()`, `.enableMultipleSubjects(SubjectResultOptions.Builder().enableConfidenceMask().build())`.
- Client: `SubjectSegmentation.getClient(options)` → `SubjectSegmenter`;
  `InputImage.fromBitmap(bitmap, rotationDegrees)`;
  result `SubjectSegmentationResult` → `getForegroundConfidenceMask()` (a
  `FloatBuffer`), `getForegroundBitmap()`, `getSubjects()` → `Subject`
  (`getConfidenceMask()`, `getBitmap()`, bounds).
- Explicit availability/download: `ModuleInstall.getClient(context)` →
  `areModulesAvailable(api)` → `ModuleAvailabilityResponse.areModulesAvailable()`;
  `ModuleInstallRequest.newBuilder().addApi(api).build()` +
  `deferredInstall(api)`; progress via `InstallStatusListener.onInstallStatusUpdated(ModuleInstallStatusUpdate)`.
- ⚠ **Not documented on the Subject Segmentation page:** `getInitTask()` and
  `close()` are not shown in Google's sample there. `SubjectSegmenter` extends
  `Closeable`-style ML Kit `Detector`, so `close()` exists; `getInitTask()` must be
  confirmed against the resolved artifact's API in Phase 3 (a compile check settles
  it). The plan therefore treats `getInitTask()` as *use if present*, with an
  explicit `ModuleInstall` availability check as the load-bearing mechanism.

**Apple — Vision (iOS)**

- `VNGenerateForegroundInstanceMaskRequest` — **iOS 17.0+** / macOS 14+ / tvOS 17+
  / visionOS 1+. Guard with `if #available(iOS 17.0, *)`; deployment target stays 15.5.
- Returns `VNInstanceMaskObservation`; `allInstances` is the full instance index
  set; `generateScaledMaskForImage(forInstances:from:)` produces a
  **source-resolution** mask `CVPixelBuffer` from the request handler.
- Canonical shape:
  ```swift
  let request = VNGenerateForegroundInstanceMaskRequest()
  let handler = VNImageRequestHandler(cgImage: image)
  try handler.perform([request])
  guard let result = request.results?.first else { /* no subject → fallback */ }
  let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances,
                                                   from: handler)
  ```
- The interactive VisionKit lift-subject UI is **not** used.

Sources: [ML Kit Subject Segmentation (Android)](https://developers.google.com/ml-kit/vision/subject-segmentation/android) ·
[Module Install APIs](https://developers.google.com/android/guides/module-install-apis) ·
[VNGenerateForegroundInstanceMaskRequest](https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest) ·
[generateScaledMaskForImage(forInstances:from:)](https://developer.apple.com/documentation/vision/vninstancemaskobservation/generatescaledmaskforimage(forinstances:from:))

---

## 2. Target state

```text
Pick image
  └─ pickAndCompress()  →  ONE Uint8List (the single source of truth)
       ├────────────────────────────────────────────┐
       │ local engine (gated)                       │ upload (unchanged)
       ▼                                            ▼
  LocalCutoutOrchestrator                    POST /v1/media/upload-url
   1 gates: master + platform                 → presigned PUT → R2
   2 platform capability probe                 → object_key
   3 Android: bounded model prepare
   4 native removal, bounded timeout
   5 validate files + metrics (quality policy)
       │
       ├─ ACCEPTED ────────────────────────────────────────────────┐
       │    show local cutout preview IMMEDIATELY                  │
       │    POST /v1/wardrobe/local-cutout (multipart, gated)       │
       │      original_object_key + mask PNG + engine metadata      │
       │      server: prefix/ownership check → download original    │
       │              → normalize_source_image (SHARED helper)      │
       │              → decode_uploaded_mask + exact dim match      │
       │              → sanitize_soft_mask → compose_cutout_png     │
       │              → put(cutout, thumb) + put(mask)              │
       │              → item INSERT cutout_status='done'            │
       │                 + original/cutout/cutout_mask ledger rows  │
       │              → NO KIND_REMBG signal, zero-cost usage log   │
       │      → WardrobeItemResponse with signed URLs               │
       │    → existing confirm/name/category flow                   │
       └─ REJECTED / UNSUPPORTED / TIMEOUT / VALIDATION FAILURE ────┘
              │ reuse the SAME object_key
              ▼
         POST /v1/wardrobe  (today's path, byte-for-byte)
         cutout_status='queued' → queue → Azure BiRefNet → poll → reveal

Later, on a saved item:
  "Improve edges" → POST /v1/wardrobe/{id}/improve-cutout (free, gated,
                    rate-limited) → re-queue for BiRefNet, current cutout stays
                    live throughout; failure keeps the old cutout
  "Fix cutout"    → existing Erase/Restore editor → PUT /cutout-mask (unchanged)
```

Invariants: local success **never** enqueues `KIND_REMBG`; the local and cloud
paths **never** both own a new item; the compressed JPEG uploaded as the original
is byte-identical to what the native engine segmented.

---

## 3. Files to change (by phase)

Nothing outside this list is expected to change. `*` = new file.

**Phase 1 — dormant contracts**
- `app/lib/core/config/feature_gates.dart` — add `kLocalBgRemovalEnabled`,
  `kLocalBgAndroidEnabled`, `kLocalBgIosEnabled` (all `defaultValue: false`).
- `app/lib/features/wardrobe/local_cutout/local_cutout_models.dart` *
- `app/lib/features/wardrobe/local_cutout/local_cutout_platform.dart` * (channel
  name `wtm/background_removal`, method + typed error-code constants)
- `app/lib/features/wardrobe/local_cutout/local_cutout_quality_policy.dart` *
- `app/lib/features/wardrobe/local_cutout/local_cutout_cache.dart` *
- `app/test/features/local_cutout/…` * (fakes + policy/serialization tests)
- `backend/app/core/config.py` — `local_cutout_upload_enabled: bool = False`
  (+ `local_cutout_improve_enabled: bool = False`).
- `backend/app/services/bg/mask_ingest.py` * — extract `_apply_uploaded_mask()`
  from `routers/v1/wardrobe.py` into a shared, unit-testable service used by
  **both** the editor endpoint and the new local endpoint. The editor's observable
  behaviour must not change.
- `backend/.env.example`, `app/env/{dev,staging,prod}.json.example`, `LICENSES.md`,
  this document.

**Phase 2 — backend ingestion**
- `backend/app/routers/v1/wardrobe.py` — `POST /v1/wardrobe/local-cutout`; factor
  the item-insert + ledger-insert shared with `POST /v1/wardrobe`.
- `backend/app/models/wardrobe.py` — `LocalCutoutCreate` form model.
- `backend/app/services/media/repo.py` — a `install_local_cutout_assets()` sibling
  of `replace_cutout_assets()` if the insert-path differs enough to warrant it.
- `backend/app/tests/test_local_cutout.py` *
- Migration `0049_*.sql` — **only if** §5 concludes it is necessary.

**Phase 3 — Android engine**
- `app/android/app/build.gradle.kts` (`minSdk` 24 + ML Kit dep),
  `app/pubspec.yaml` (`flutter_launcher_icons.min_sdk_android: 24`),
  `app/android/app/src/main/AndroidManifest.xml` (`DEPENDENCIES` meta-data),
  `MainActivity.kt` (small registration hook only),
  `app/android/app/src/main/kotlin/com/fashionos/app/background/*.kt` *,
  `app/android/app/src/test/kotlin/…` * (JVM unit tests).

**Phase 4 — iOS engine**
- `app/ios/Runner/BackgroundRemoval/*.swift` *,
  `AppDelegate.swift` (one registration line),
  `app/ios/Runner.xcodeproj/project.pbxproj` (add files to the target).
  Deployment target, signing, bundle id, entitlements, Info.plist: **unchanged**.

**Phase 5 — orchestration**
- `app/lib/features/wardrobe/local_cutout/local_cutout_service.dart` *,
  `local_cutout_orchestrator.dart` *, `local_cutout_providers.dart` *
- `app/lib/data/repositories/wardrobe_repository.dart` —
  `addItemWithLocalCutout(...)` (new method, `addItem()` untouched).
- `app/lib/ui/closet/wtm_add_garment_screen.dart` — local-first branch + honest copy.
- `app/lib/l10n/app_en.arb` — new strings.

**Phase 6 — improvement + resilience**
- `backend/app/routers/v1/wardrobe.py` (`POST /{item_id}/improve-cutout`),
  `wardrobe_repository.dart` (`requestBiRefNetImprovement`),
  `wtm_add_garment_screen.dart` + `wtm_garment_detail_screen.dart` (the button),
  `app/lib/data/models/wardrobe_item.dart` (a derived "improving" getter — no
  breaking JSON change), tests on both sides.

**Phase 7–9** — analytics (`core/analytics/analytics_events.dart`), structured
backend logs, stale-cache cleanup, `LICENSES.md`, runbooks, test/QA/rollout docs.

---

## 4. Exact endpoint proposal

### 4.1 `POST /v1/wardrobe/local-cutout`

```http
POST /v1/wardrobe/local-cutout
Authorization: Bearer <supabase jwt>
Content-Type: multipart/form-data

original_object_key : str   required, ≤512  — an existing private R2 wardrobe key
mask                : file  required        — lossless PNG, grayscale or alpha
engine              : str   required        — "apple_vision" | "google_mlkit"
engine_version      : str   optional, ≤64
platform            : str   required        — "ios" | "android"
local_latency_ms    : int   optional, 0..600000
subject_count       : int   optional, 0..64
metrics_json        : str   optional, ≤2048 — advisory only, never trusted
title, category     : str   optional        — parity with POST /v1/wardrobe
```

Ordered behaviour:

1. `local_cutout_upload_enabled` false → **404 `NOT_FOUND`** (invisible, exactly
   like the editor gate).
2. `r2_writes_enabled` false → **503 `PROVIDER_ERROR`** → the app uses the cloud flow.
3. `original_object_key` must start with `f"{user.id}/wardrobe/"` and contain no
   `..` or `//` → else **403 `NOT_FOUND`-shaped** (use `NOT_FOUND` 404 so the
   endpoint never confirms another user's key exists).
4. Read the mask with the existing `_read_capped(upload, bg_mask_upload_max_bytes)`
   → **413 `VALIDATION_ERROR`** past the cap, before any decode.
5. Rate limit `enforce_rate_limit(bucket=f"local_cutout:{user.id}", …)`.
6. **Idempotency check** (§5) — an existing item for this key short-circuits to a
   200 with that item.
7. Download the stored original via the R2 provider, `normalize_source_image(...,
   max_edge=bg_max_image_edge)`.
8. `decode_uploaded_mask` → require `mask.size == (norm.width, norm.height)`
   exactly → `sanitize_soft_mask` (near-extreme snapping only; §5.1 of the prompt
   is satisfied by the existing `_ALPHA_FLOOR=3` / `_ALPHA_CEIL=252` LUT) →
   server-side alpha-area sanity `0.005 ≤ mean_alpha_area ≤ 0.998` →
   **422 `VALIDATION_ERROR`** on any failure. *No item is created.*
9. `compose_cutout_png` + `encode_mask_png` in `asyncio.to_thread`.
10. `provider.put(cutout, private, prefix "{uid}/cutout", make_thumbnail=True)`
    and `provider.put(mask, private, prefix "{uid}/cutout-mask", make_thumbnail=False)`
    — same prefixes and content types the worker uses.
11. One transaction: insert `wardrobe_items` with `cutout_status='done'`,
    `cutout_url=<cutout key>`, `thumbnail_url=<cutout key>`, `attempt_count=0`,
    `cutout_locked_at=NULL`, `cutout_last_signal_at=NULL`; then three
    `insert_asset` rows — `original` (the supplied key), `cutout`, `cutout_mask`.
12. On DB failure: best-effort delete the **newly uploaded** cutout + mask objects
    (reuse `_safe_delete_object`), never the original, then re-raise.
13. **Never** `enqueue_signal(KIND_REMBG, …)`.
14. `ai_usage_log` row: `provider=f"local:{engine}"`, `task='bg_removal'`,
    `images=1`, `estimated_usd=0`, `latency_ms=<server total>`, `success=true`.
    Zero credits, no membership check — identical posture to the editor endpoint.
15. Return the normal `WardrobeItemResponse` through `_with_media()` (201 on
    create, 200 on idempotent replay).
16. Best-effort `enqueue_signal(KIND_ENRICHMENT, item_id)` **after** commit so
    tagging/embedding still happen off the visual critical path. This is the
    enrichment queue, not the rembg queue — it cannot trigger a cutout.

### 4.2 `POST /v1/wardrobe/{item_id}/improve-cutout`

```http
POST /v1/wardrobe/{item_id}/improve-cutout      → 202 + WardrobeItemResponse
```

- Gate `local_cutout_improve_enabled` (404 when off); R2 not required to *queue*,
  but the worker needs it, so keep the same 503 guard for consistency.
- Ownership: `where id = $1 and user_id = $2` → 404 otherwise.
- Free: no credits, no entitlement check. Rate-limited
  (`bucket=f"improve_cutout:{user.id}"`, ~6 per 10 min).
- **Duplicate-tap guard:** only transition when
  `cutout_status not in ('queued','processing')`; a row already in flight returns
  the current item unchanged (202, no new work).
- The update sets `cutout_status='queued'`, `attempt_count = 0`,
  `cutout_error_code = NULL`, `cutout_locked_at = NULL`,
  `cutout_last_signal_at = NULL` and **leaves `cutout_url`, `thumbnail_url` and
  every `media_assets` row untouched** — that is what keeps the current cutout on
  screen (§1.5). Resetting `attempt_count` is mandatory: the worker fails a row
  outright when `attempt_count > max_attempts`, so an item that already burnt its
  budget would otherwise be marked `failed` instantly.
- After commit, best-effort `enqueue_signal(KIND_REMBG, item_id)`; stamp
  `cutout_last_signal_at` **only** on a successful enqueue, so recovery's
  stranded-`queued` scan is the backstop (unchanged semantics).
- Worker success replaces cutout + mask atomically via the existing
  `replace_cutout_assets()`. Worker failure leaves the previous objects in place
  (verified in §1.5) — Phase 6 adds regression tests for exactly this and hides
  the `failed` badge when a valid `cutout_url` still exists.

---

## 5. Idempotency strategy and migration decision

**Request identity = the original R2 object key.** It is server-generated,
`uuid4().hex`-random, and scoped to `{user_id}/wardrobe/`, so it is a natural
single-use token for "this one picked photo".

The check, inside the same transaction that would create the item:

```sql
select w.id
  from public.media_assets m
  join public.wardrobe_items w
    on w.id = m.owner_id and w.user_id = $2::uuid
 where m.owner_kind = 'wardrobe_item'
   and m.role = 'original'
   and m.object_key = $1
   and m.deleted_at is null
 limit 1
```

A hit → return that item (no new item, no duplicate ledger rows, no queue
signal). This covers the two cases that matter: a lost response after a
successful commit, and an app retry after a transient network error.

**Concurrency.** Two *simultaneous* requests with the same key could both miss the
check. Rather than add a schema constraint, Phase 2 will take
`pg_advisory_xact_lock(hashtext($1))` on the object key at the top of the
transaction. That serialises same-key requests, needs no migration, and is
released automatically at commit/rollback.

**Migration decision: NO migration is required.** Reasoning:

- `cutout_status='done'` on insert needs no schema change (`0002` already defines
  the column; `role='cutout_mask'` is free-form text, as `BIREFNET_CUTOUT_RUNBOOK.md`
  records).
- A partial unique index on `media_assets (object_key) where object_key is not
  null and deleted_at is null` would be the "textbook" guard, but it is **not
  safe to add blind**: `_replace_role_asset()` soft-deletes displaced rows rather
  than deleting them, the 1C backfill wrote rows this audit cannot inspect from
  here, and a `CREATE UNIQUE INDEX` that fails on pre-existing duplicates would
  break a production migration run. The advisory lock achieves the same guarantee
  with zero schema risk.
- If the founder later wants the index as defence-in-depth, it should be its own
  migration **after** an owner-run duplicate audit
  (`select object_key, count(*) … group by 1 having count(*) > 1`). Recorded here
  as a follow-up, deliberately not done in this project.

Next free migration number, if one ever becomes necessary: **`0049`**.

---

## 6. Licensing

`play-services-mlkit-subject-segmentation` is delivered through Google Play
services and governed by the [ML Kit Terms of Service](https://developers.google.com/ml-kit/terms).
On-device subject segmentation is free and commercially permitted, and no image
leaves the device. This is the **same** arrangement already accepted and recorded
in `LICENSES.md` for `google_mlkit_pose_detection`, so it introduces no new
licence class. Apple Vision ships with iOS under the Apple SDK licence. **No paid
provider is added; BiRefNet General Lite (Apache-2.0) remains the fallback.**
`LICENSES.md` gets both rows in Phase 1.

---

## 7. Risk register

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | ML Kit Subject Segmentation is still `16.0.0-beta1` | Med | Pin explicitly; re-verify at Phase 3; the whole path is behind `LOCAL_BG_ANDROID_ENABLED=false` and falls back to BiRefNet on any error |
| R2 | `minSdk` 23 → 24 drops Android 6.0 (Marshmallow) devices | Med | ~0.3 % of the Play install base and the app already requires API 23 for Credential Manager. **Needs an explicit founder OK before Phase 3** — it changes store eligibility for existing users |
| R3 | Local mask dimensions disagree with the backend's normalized original | High | Same bytes on both sides; EXIF already stripped by `keepExif: false`, so `exif_transpose` is a no-op; server requires an exact match and rejects otherwise (→ cloud fallback, no data loss) |
| R4 | Local + cloud both create an item for one photo | High | Dedicated create endpoint (never "create queued then race"); idempotency by object key + advisory lock; the app only falls back **after** a definitive validation failure, and reuses the same key |
| R5 | Duplicate active `media_assets` rows | Med | Insert exactly three rows in one transaction; the idempotent replay path inserts none; Phase 2 asserts row counts |
| R6 | Item marked `done` before its objects exist | High | Objects are uploaded **before** the DB transaction; DB failure deletes the new objects and creates no item |
| R7 | `attempt_count` poisons an improvement request | Med | Reset `attempt_count`/`cutout_error_code`/lease on re-queue (§4.2); regression test |
| R8 | Improvement failure wipes a good cutout | High | Verified today's `_mark_failed()` does not clear `cutout_url` (§1.5); Phase 6 adds a regression test and hides the failed badge when a cutout exists |
| R9 | Native OOM / UI jank on large bitmaps | Med | Work off the main thread, one operation at a time, recycle bitmaps, cache files instead of channel byte arrays, no duplicate full-res bitmap outputs |
| R10 | Temp cache files leak | Low | Dart owns cleanup on success/failure/cancel/dispose + a startup sweep of stale operation dirs |
| R11 | Channel not registered → every add breaks | High | Capability probe is the first call and any `MissingPluginException` maps to `unsupported` → cloud fallback; plus gates default OFF |
| R12 | Sensitive data in logs | High | Metrics buckets only; never bytes, keys, signed URLs, tokens or paths containing identifiers; a log-content test where practical |
| R13 | iOS 17 symbols break the 15.5 build | Med | `if #available(iOS 17.0, *)` + a typed `unsupportedOs` result; Codemagic `flutter build ios --release --no-codesign` is the gate |
| R14 | Regression in AI Enhance / credits / paywall | High | Those code paths are not edited; full suites each phase; explicit "AI Enhance unchanged" test |
| R15 | `_replace_role_asset()` assumes exactly one active row per role | Low | The new path inserts fresh rows for a brand-new item; a later improvement goes through the existing `replace_cutout_assets()`, which already collapses duplicates |
| R16 | Aggressive quality thresholds send everyone to the 90 s+ fallback | Med | Hard rejection only for structural failure (`0.01 ≤ area ≤ 0.995`, `subjectCount ≥ 1`); everything else is a soft warning that keeps the local result |
| R17 | The legacy non-WTM add flow bit-rots | Low | Left untouched; its tests stay in the suite |
| R18 | Azure `wtm-rembg-job` config drift | High | No infra change in any phase; `BG_MODEL` / `BG_MASK_PIPELINE_V2` / 4 vCPU-8 GiB untouched; all commands in the rollout runbook are for the human operator |

---

## 8. Test plan

Deterministic and network-free everywhere except the manual device matrix.

**Backend (`pytest`, currently 699 passing)** — new `test_local_cutout.py`,
following `test_wardrobe.py`'s harness (HS256 JWT + `TestClient`, `monkeypatch`
env + `get_settings.cache_clear()`, `_enable_r2()`, `raise_server_exceptions=False`
for the DB-layer probes) and `test_bg_pipeline.py`'s pure-helper style for imaging:

gate off → 404 · R2 off → 503 · wrong-user prefix → 404 · traversal key → 404 ·
oversized mask → 413 before decode · non-PNG → 422 · malformed → 422 · wrong
dimensions → 422 · empty mask → 422 · near-full mask → 422 · missing original →
422 · soft-alpha preserved byte-exactly through the shared helper · success
creates `cutout_status='done'` with 3 ledger rows · **no `KIND_REMBG` enqueue on
success** · storage failure creates no item · DB failure deletes the new objects
and not the original · idempotent replay returns the same item with no second
item / ledger row / signal · zero-cost `ai_usage_log` · `POST /v1/wardrobe` still
queues BiRefNet · improvement: ownership, duplicate-tap no-op, field resets,
cutout retained on worker failure, atomic replacement on success · deletion still
sweeps original + cutout + cutout_mask · recovery does not treat a `done` local
item as stale work · existing editor tests unchanged.

**Dart (`flutter test`, currently 632 passing)** — quality-policy unit tests
(boundary values, NaN/inf), contract serialization, orchestrator tests against a
fake platform + fake repository: gate off · iOS <17 · Android unsupported /
Play-services missing / model-download failed · local timeout · hard rejection ·
soft warning accepted · successful persistence · transient retry (once) ·
validation failure → cloud fallback **with the same object key** · lost response →
no duplicate · temp cleanup on success / failure / cancel / dispose · duplicate-tap
guard · Improve edges · existing Fix-cutout navigation · AI Enhance unchanged ·
widget test that the processing state renders the local preview before
persistence completes.

**Android native** — JVM unit tests behind an interface that wraps the ML Kit
client (no model download): `FloatBuffer` → soft-alpha conversion, dimension
mapping, compositing, metrics, empty/full masks, multi-subject mapping, cache
file lifecycle, typed error mapping, `close()`, single-concurrent-operation.

**iOS native** — pure-helper tests where the harness allows (mask pixel-buffer
conversion, compositing, metrics, cache cleanup, unsupported-version response) +
the authoritative gate: `flutter build ios --release --no-codesign` via the
existing `ios-compile-check` workflow, signing untouched.

**Full regression each phase**
```bash
cd app && flutter pub get && flutter analyze && flutter test
cd backend && .venv/Scripts/python -m pytest -q
```
Android compile check (Phase 3+): `cd app && flutter build apk --debug`. No AAB,
no IPA, no version bump, no deploy.

---

## 9. Open questions for the founder

1. **R2 (blocking for Phase 3):** `minSdk` 23 → 24 is mandatory for ML Kit Subject
   Segmentation and drops Android 6.0. Confirm.
2. **Branch base:** keep `feat/local-first-background-removal` on
   `migration/heroku-azure` (recommended, see the deviation note), or re-cut it
   from `origin/main`?
3. **`media_assets.object_key` unique index:** leave as a documented follow-up
   (recommended), or schedule the owner-run duplicate audit + migration `0049`?
