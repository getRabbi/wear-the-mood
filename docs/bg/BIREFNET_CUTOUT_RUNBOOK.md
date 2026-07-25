# BiRefNet Lite cutout + free Erase/Restore editor — production runbook

Staged, reversible rollout for the background-removal upgrade
(`feat/birefnet-lite-cutout-v2`). Every stage is **operator-controlled**; deploying
the code changes **nothing** until the flags are flipped.

> **Infra note.** Production runs on **Heroku (API) + Azure Container Apps Jobs
> (`wtm-rembg-job` worker)** since the 2026-07-20 cutover; the **DigitalOcean
> `docker-compose.yml`** stack is the rollback bridge. Commands are given for
> **both**. Do NOT run any of these from Claude Code — they are for the human
> operator.

## What changed (summary)

| Area | Before | After (dormant until flags flip) |
|---|---|---|
| Model | rembg default U2Net composite | rembg session model from `BG_MODEL` (`u2net` **or** `birefnet-general-lite`) |
| Pipeline | rembg default composite | `BG_MASK_PIPELINE_V2=true` → normalize → soft-alpha **mask-only** inference → composite → persist an editable `cutout_mask` |
| Correction | none | free `PUT /v1/wardrobe/{id}/cutout-mask` + a gated Flutter Erase/Restore editor (no credits, no AI) |

- **No DB migration.** `media_assets.role` is free-form text; `cutout_mask` needs no schema change. No destructive SQL. `FASHIONOS_BASELINE.sql` untouched.
- **Backward compatible.** `WardrobeItemResponse` is unchanged; old app builds never learn about `cutout_mask`. Existing cutouts stay valid.
- **Never auto-reprocesses** existing wardrobe items.

## Defaults (Stage 1 — deploy dormant)

```env
BG_MODEL=u2net
BG_MASK_PIPELINE_V2=false
CUTOUT_EDITOR_ENABLED=false
BG_MASK_UPLOAD_MAX_BYTES=4000000
BG_MAX_IMAGE_EDGE=4096
```

Deploying the reviewed commit with these defaults is a **no-op** for behaviour.
Ship it, confirm health, then proceed to Stage 2 only when ready.

---

## Stage 2 — activate the automatic model (worker only)

First back up the production DB with the existing process, then:

### Verify the model constructs (do this first, on either platform)

```bash
# inside the worker image / venv (has rembg):
python -m app.scripts.prefetch_bg_model --model birefnet-general-lite --smoke
# exits 0 and logs "model 'birefnet-general-lite' ready" + a mask/cutout smoke pass
```

### A) Azure (live production) — `wtm-rembg-job`

The rembg image **bakes** its model at build time (`backend/rembg-worker.Dockerfile`,
`ARG REMBG_MODEL`) and pins it as the runtime `REMBG_MODEL` env, which
`Settings.background_model` honours. So:

1. Build + push the rembg image with BiRefNet baked (via CI
   `.github/workflows/migration-build.yml`, changing the rembg `build_args` to
   `REMBG_MODEL=birefnet-general-lite`, or an equivalent manual build):
   ```bash
   docker build -f backend/rembg-worker.Dockerfile \
     --build-arg REMBG_MODEL=birefnet-general-lite \
     -t <ghcr>/wtm-rembg-worker:birefnet backend
   ```
   The build **fails closed** if the model can't download + verify, so a bad image
   never ships.
2. Point `wtm-rembg-job` at the new image digest and set the pipeline flag:
   ```bash
   az containerapp job update -g wtm-prod -n wtm-rembg-job \
     --image <ghcr>/wtm-rembg-worker@sha256:<new> \
     --set-env-vars BG_MASK_PIPELINE_V2=true BG_MODEL=birefnet-general-lite
   ```
   (`BG_MODEL` is redundant with the baked `REMBG_MODEL` but makes the intent
   explicit.) No other job/app is touched; the API is unaffected.

### B) DigitalOcean bridge (`docker-compose.yml` worker)

The worker mounts the persistent `rembg-models` volume at `/models`
(`U2NET_HOME`). Prefetch into it, then flip the flags:

```bash
ssh root@159.65.248.247
cd /path/to/repo && git fetch && git checkout <reviewed-commit>
# 1) download birefnet into the existing model volume:
docker compose run --rm worker python -m app.scripts.prefetch_bg_model \
  --model birefnet-general-lite --smoke
# 2) set the knobs in the ROOT .env (same place as GIT_SHA / API_DOMAIN):
#      BG_MODEL=birefnet-general-lite
#      BG_MASK_PIPELINE_V2=true
# 3) recreate ONLY the worker so it picks up the env (API untouched):
docker compose up -d worker
```

### Confirm (either platform)

Watch the worker start log: `rembg remover ready model=birefnet-general-lite
mask_pipeline_v2=True`. Then upload **one new** garment through production and check:

- `cutout_status`: queued → processing → done
- original still resolves; cutout resolves; thumbnail resolves
- a `media_assets` row with `role='cutout_mask'` now exists for the item
- tagging still runs; **no credits charged**; worker memory stable
- **do not** reprocess old items

> **⚠ Memory headroom (verified finding).** birefnet-general-lite's ONNX inference
> is memory-heavy — it OOM-killed (exit 137) in a **3.8 GiB** Docker test box on a
> single-image inference (it *constructs* + *bakes* fine below that; the inference
> pass is what peaks). The Azure `wtm-rembg-worker` is provisioned at **2 vCPU /
> 4 GiB**, a narrow margin. During Stage 2, watch the first real inference's peak
> memory; if it nears the cap, bump the ACA Job's memory (e.g. 6 GiB) before wider
> rollout. u2net stays comfortably within 4 GiB, so rollback is unaffected.

---

## Stage 3 — activate the free editor (API + app)

Only after the endpoint is verified live:

1. API env: `CUTOUT_EDITOR_ENABLED=true`, then restart the API.
   - Azure: `az containerapp update -g wtm-prod -n <api-app> --set-env-vars CUTOUT_EDITOR_ENABLED=true` (or the Heroku config var, per the live host).
   - DO bridge: set `CUTOUT_EDITOR_ENABLED=true` in the root `.env`, `docker compose up -d api`.
2. Requires R2 private writes (`STORAGE_WRITES=r2` + real R2 creds). Without them
   the endpoint returns a clear `PROVIDER_ERROR` (503) and the editor stays hidden.
3. Build the Flutter release with the compile-time gate on:
   ```bash
   flutter build appbundle --dart-define-from-file=env/prod.json \
     --dart-define=CUTOUT_EDITOR_ENABLED=true
   ```
   Release through the normal store process. Old builds without the define simply
   never show "Fix cutout".

---

## Rollback — automatic model

```env
BG_MODEL=u2net
BG_MASK_PIPELINE_V2=false
```

Restart **only the worker** (Azure: `az containerapp job update ... --set-env-vars
BG_MASK_PIPELINE_V2=false BG_MODEL=u2net`; DO: edit root `.env`, `docker compose up
-d worker`). BiRefNet-created cutouts + masks **remain valid**. Do **not** delete
model files, masks or cutouts.

## Rollback — editor

```env
CUTOUT_EDITOR_ENABLED=false
```

Restart the API. The endpoint 404s again; already-corrected assets remain valid.
Ship an app build without the Dart define when convenient.

---

## Notes / guarantees

- Try-on, AI Enhance, credits, subscriptions, tagging, embeddings, community and
  profile flows are unchanged.
- The correction endpoint spends no credits and calls no AI/membership logic.
- Item deletion + account deletion already sweep every `media_assets` role, so
  `cutout_mask` objects are erased with the rest — no new deletion code.
- `BG_MASK_UPLOAD_MAX_BYTES` / `BG_MAX_IMAGE_EDGE` bound upload size + guard against
  decompression bombs; tune only with care.
