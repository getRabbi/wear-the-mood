# Backend-first deploy — try-on timing instrumentation

**Status: EXECUTED 2026-08-11, Scope B. See §8 for the outcome.**

Production cannot emit the new correlated timing logs because nothing on this
branch is deployed. This is the smallest deployment that unblocks the device
measurement in `TRYON_TIMING_MEASUREMENT.md`.

Nothing here merges `main`, releases the app, or touches the database.

---

## 1. Where production is right now (verified 2026-08-11)

| Component | State | Rollback anchor |
|---|---|---|
| **Heroku** `wtm-api-prod` | Release **v35**, image `8131fc877256` (released v34, 2026-08-10 08:56Z), `GIT_SHA=f933367` | `heroku rollback v35 -a wtm-api-prod` |
| **Azure** `wtm-ai-orchestrator-job` | `ghcr.io/getrabbi/wtm-orchestrator@sha256:14b0e103c913bad2b510032958c00dcffcbdbf565f38a0306280bd52b9951d77` | re-pin that digest |
| **Azure** `wtm-rembg-job` | `wtm-rembg-worker@sha256:ae26642315bf…` (BiRefNet Lite) | **must not change** |
| 11 other Azure jobs | 8 on `14b0e103c913…`, 3 on `e77cddc160de…` | **not in scope** |
| Database | Supabase `ghzabbceoaoertatkjyg` (us-east-1) | **not touched** |

`GIT_SHA=f933367` is exactly this branch's base commit, so production is running
the merge point and the deploy is a clean fast-forward of backend code only.

---

## 2. What would change

Branch `fix/production-eight-defects` @ `824f3c3`. Backend diff vs production:

```
backend/app/core/timing.py          | 105 +++++  NEW — the stage timer
backend/app/routers/v1/tryon.py     |  31 +++    submit-side stages
backend/app/workers/tryon_worker.py |  31 +++    worker-side stages
backend/app/services/tryon/fashn.py |  10 +++    provider accept vs inference
backend/app/workers/claim.py        |   2 +-     +idempotency_key in RETURNING
backend/app/routers/v1/news.py      |  51 +++    NEW GET /v1/news/{id}
backend/app/routers/v1/wardrobe.py  |  23 +++    optional limit + before
backend/app/routers/v1/giveaways.py |  18 +++    optional after cursor
backend/app/services/push/*         |  34 +++    FCM icon field  <- SEE §3
backend/app/tests/*                 | 256 +++    tests only, not shipped
```

**Not deployed by this:** every Flutter change (needs an app release), the
Android notification drawables (ditto), and all documentation.

### Why each piece is safe

* **Instrumentation** — additive logging only. No reordering, no provider
  setting, no poll cadence, no credit rule, and no extra request. A test asserts
  the timing module never imports `httpx`, `asyncpg`, the pool or the queue.
* **`GET /v1/news/{id}`** — a brand-new route. Nothing calls it until the app
  ships, so it cannot regress anything.
* **`limit` / `before` on `/v1/wardrobe`, `after` on chat messages** — optional
  query parameters with defaults that reproduce today's behaviour exactly. The
  installed app sends none of them and gets byte-identical responses.
* **`idempotency_key` in the claim RETURNING** — one extra existing column.
  Old-image jobs and new-image jobs can run side by side; nothing reads it but
  the trace token.

---

## 3. The one behaviour change — decide before deploying

`services/push/fcm.py` now always sends an `AndroidConfig` carrying
`icon: "ic_stat_wtm"`. **The installed app does not have that drawable** — it
ships with the app release, not this one.

Verified: `channel_id=None` is omitted rather than serialised as null, so
messages without a channel still deliver and still land on the manifest default
channel.

```
with a channel   -> {'icon': 'ic_stat_wtm', 'channel_id': 'wtm_social'}
without a channel -> {'icon': 'ic_stat_wtm'}
```

An icon name the app cannot resolve falls back through FCM's normal chain to the
launcher icon — which is exactly the blank square users already see. So the
expected outcome is *no observable change*. But that is a documented fallback I
have not confirmed on a device, and push delivery is how try-on results reach
people.

**Two scopes, therefore:**

| | Scope | Includes FCM icon | Behaviour change on the installed app |
|---|---|---|---|
| **B** | **Minimal (recommended)** | No | **None at all** |
| **A** | Whole branch backend | Yes | Expected none; unverified fallback |

Scope B is one command to prepare — a deploy branch with `services/push/`
reverted to the production commit:

```bash
git switch -c deploy/timing-instrumentation fix/production-eight-defects
git checkout f933367 -- backend/app/services/push/
git commit -m "chore(deploy): hold the FCM icon field until the app ships it"
git push -u origin deploy/timing-instrumentation
```

The FCM field then ships with the next backend deploy, alongside the app release
that actually contains the drawable — which is when it starts mattering.

---

## 4. Pre-deploy checks already done

| Check | Result |
|---|---|
| Backend tests (pinned venv) | 1340 passed |
| `ruff check` / `ruff format --check` | Pass, 295 files |
| New SQL prepared against **live production** | **5/5 valid** — prepare-only, no execute, no write |
| FCM payload serialisation | Verified (§3) |
| `LOG_LEVEL` on prod | Unset → config default `INFO` → the timing lines will appear |
| Dependencies | `requirements.txt` unchanged; `timing.py` is stdlib-only |
| Branch push | Fired no workflow — verified against `gh run list` |

The live SQL check used `asyncpg.prepare()`, which sends Parse/Describe and does
not execute. The DSN came from `heroku config` (never from the stale
`backend/.env.prod`) and was never printed.

**Staging is not a useful rehearsal here** and is not in the plan: it is 21 days
stale (`18bb4ac`, 2026-07-20), so deploying to it would exercise three weeks of
unrelated drift, and it shares the *production* `CONNECTION_STRING` and Supabase
project, so it is not an isolated environment either.

---

## 5. Deployment — on approval, in this order

### Step 1 — Heroku API

```bash
gh workflow run migration-deploy.yml \
  --ref <deploy/timing-instrumentation | fix/production-eight-defects> \
  -f target=prod
```

Stops at the `production` GitHub Environment's required review. Approve it there
— that gate is the point of using CI rather than a hand push.

Verify before continuing:

```bash
heroku releases -a wtm-api-prod -n 3
curl -sS https://api.wearthemood.com/healthz
curl -sS https://api.wearthemood.com/readyz     # expect {"db":true,…}
```

> Do **not** trust `/readyz`'s `commit` field alone — it reads the `GIT_SHA`
> config var, which has drifted from the image before. Compare the release
> timestamp too.

**Stop here if anything is wrong.** Azure is untouched at this point and
rollback is one command.

### Step 2 — Azure orchestrator image

```bash
gh workflow run migration-build.yml --ref <same ref>
```

Builds and pushes four images to GHCR. Take the **`wtm-orchestrator` digest**
from the "record immutable digest" step.

> The run also moves the floating `migration-candidate` tag on
> `wtm-rembg-worker`. Harmless — every Azure job pins by digest, verified. But
> **never** point `wtm-rembg-job` at that output: the generic image does not bake
> `BG_MODEL=birefnet-general-lite` and dies with `PermissionError` on read-only
> `/models`.

### Step 3 — Repoint ONLY the orchestrator job

```bash
az containerapp job update -g wtm-prod -n wtm-ai-orchestrator-job \
  --image ghcr.io/getrabbi/wtm-orchestrator@sha256:<new digest>
```

`az` writes progress to stderr, so PowerShell reports a failure on success.
**Verify against API state, never the exit code:**

```bash
az containerapp job show -g wtm-prod -n wtm-ai-orchestrator-job \
  --query "properties.template.containers[0].image" -o tsv
```

Env vars are preserved by `--set`-less image updates, so
`LOCAL_CUTOUT_UPLOAD_ENABLED` (which every prod process needs or it refuses to
start) stays in place. Confirm the count is unchanged if you want belt and
braces.

### Step 4 — Prove the logs flow

One ordinary try-on, then:

```bash
heroku logs --app wtm-api-prod --num 500 | grep "tryon.submit"
az containerapp job logs show -g wtm-prod -n wtm-ai-orchestrator-job \
  --container orchestrator --tail 200 | grep "tryon.worker"
```

Both lines must carry the same `trace=` token. Once they do, the device
measurement in `TRYON_TIMING_MEASUREMENT.md` can run.

---

## 6. Rollback

Both targets restore a known-good pinned artifact. Neither touches data, so
there is nothing to reconcile afterwards.

### Heroku — instant

```bash
heroku rollback v35 -a wtm-api-prod
heroku releases -a wtm-api-prod -n 3
curl -sS https://api.wearthemood.com/readyz
```

`v35` is the current state (image `8131fc877256` + `GIT_SHA=f933367`). Rolling
back creates a new release restoring it; it does not rewrite history.

### Azure — one command

```bash
az containerapp job update -g wtm-prod -n wtm-ai-orchestrator-job \
  --image ghcr.io/getrabbi/wtm-orchestrator@sha256:14b0e103c913bad2b510032958c00dcffcbdbf565f38a0306280bd52b9951d77

az containerapp job show -g wtm-prod -n wtm-ai-orchestrator-job \
  --query "properties.template.containers[0].image" -o tsv
```

In-flight executions finish on the image they started with; the next execution
picks up the restored digest.

### What rollback does NOT need

* **No database work.** No migration ran, no column was added, no row changed.
* **No app release.** Nothing shipped to a device.
* **No `main.bicep` apply.** Applying it wholesale would stop every prod cron and
  break rembg — it is never part of this or its rollback.

### Triggers

Roll back if `/readyz` is not `db:true`, `/healthz` is non-200, error rate or
latency rises after Step 1, the orchestrator's first execution fails after
Step 3, or a try-on stops reaching `done`.

---

## 7. Residual risk

* **Scope A only:** the FCM icon field reaching an app that lacks the drawable
  (§3). Scope B removes this entirely.
* **Cold-start noise in the first measurement.** The orchestrator job pulls a new
  image on its next execution, so the very first try-on after Step 3 pays an
  image pull on top of the normal container start. Take the cold measurement on
  the *second* try-on after deploying, or accept that the first is
  unrepresentatively slow and say so.
* **Nothing else changes for users.** No endpoint's existing behaviour is
  altered, no schema moves, and the app on their phone is untouched.

---

## 8. Outcome — executed 2026-08-11 (Scope B)

Deployed from `deploy/timing-instrumentation` @ `dc36139`. The FCM icon field
was held back as planned, so this deploy carries **no behaviour change**.

### Result

| Target | Before | After | Verified |
|---|---|---|---|
| Heroku `wtm-api-prod` | v35, `GIT_SHA=f933367` | **v37**, image `01a40f9a1bac`, `GIT_SHA=e5ce149` | `/healthz` ok · `/readyz` `db:true` · `/v1/health` 200 · `GET /v1/news/{id}` → 401 (deployed + correctly gated) |
| Azure `wtm-ai-orchestrator-job` | `@sha256:14b0e103c913…` | **`@sha256:6128e7a4be69…`** | manual execution **Succeeded** in 43 s |
| `wtm-rembg-job` | `@sha256:ae26642315bf…` | unchanged | re-checked after the update |
| 11 other Azure jobs | — | unchanged | re-checked after the update |
| Database | — | untouched | no migration ran |

Both prod traps held: env vars survived the image update (50 vars / 12 secret
refs, `LOCAL_CUTOUT_UPLOAD_ENABLED=true` intact), and every `az` result was
verified against API state rather than an exit code.

Smoke-test execution log, which is the proof the new image boots:

```
INFO:fashionos.worker.orchestrator.batch:Fashion OS AI orchestrator BATCH job starting.
INFO:fashionos.worker.batch:orchestrator batch done: processed=0 polls=10
                            elapsed=11.9s startup=1.2s avg_job=0.00s errors=0 reason=idle
```

No `Refusing to start`, DB reachable, clean idle exit.

### One blocker hit and fixed: the secret scan

`migration-build` failed its gitleaks gate on the first attempt, which **skipped
the image matrix entirely** — tests and lint had passed. Two findings, both
false positives from the timing tests I had written: a made-up 32-hex-char
literal used as a fake idempotency key, which `generic-api-key` reads as a
high-entropy credential assigned to something called `key`.

Fixed in `dc36139`, on both branches:

* both tests now use the dashed uuid4 form the app actually mints and name the
  variable `idempotency`, so no future commit reproduces the pattern;
* one allowlist entry pinned to the exact old literal, because gitleaks runs
  `git log -p --full-history --all` and commit `380b40c` would otherwise fail
  the gate forever — rewriting a pushed branch to erase a string that was never
  secret is the worse trade.

The gate was not disabled, broadened, or path-excluded. `useDefault = true`
still keeps every real rule live.

### A measurement input, free

The smoke-test execution took **43 s wall-clock** but only **11.9 s inside the
batch**, of which app startup was **1.2 s**. So roughly **31 s of a cold
orchestrator execution is image pull + container start** — infrastructure, not
our code. That is the single biggest fixed cost in the cold path, and it is now
measured rather than estimated.

### Still outstanding

`tryon.submit` and `tryon.worker` lines have not been observed on a real
request, because that requires an actual try-on and a credit. That is the device
run in `TRYON_TIMING_MEASUREMENT.md` — which this deploy exists to unblock, and
which is now unblocked.
