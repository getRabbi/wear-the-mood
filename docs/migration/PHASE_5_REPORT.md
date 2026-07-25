# PHASE 5 REPORT — load, throughput, failure, and cost gates

**Objective:** prove the six-month architecture against the 25–30k MAU launch target before production routing.

**Objective (revised at close-out):** prove the architecture is **safe to launch on** —
not to certify 30k-MAU enterprise capacity before launch.

**Starting commit:** `b3741b9` · **Ending commit:** this commit.

**Result:** ✅ **PHASE 5 COMPLETE — all ten launch-readiness gates verified; scale
optimization deferred.** The 120 RPS gate passed outright once measured from a US-region
generator (§E1), the cost gate passed after the always-on → event-driven Jobs rework
($7.73/mo at 30k MAU vs the $16.67 ceiling; **$12/mo at launch**), and synthetic test data
was audited and removed back to the exact Phase 3 baseline (§E3). Production and DNS
untouched; Azure not routed.

> **Read this report in order.** §1–§7 are the original measurement pass and §A1–A7 the
> architecture remediation; both are kept verbatim as the audit trail, including the two
> findings they got wrong before correction. **§E is the authoritative final state** and
> supersedes the earlier 106.4 RPS caveat (§2) and the cost-gate failure (§5).

---

## 1. Data safety (§14.1)

Everything ran against the authoritative US Supabase project, so isolation was enforced structurally, not by convention:

- **40 synthetic users + 480 synthetic wardrobe items**, created per-run and deleted after.
- Every seeded item carries `cutout_status='done'` — the live DO worker only claims `'queued'` and only requeues `'processing'`, so **no seeded row was ever claimable by production**. This was asserted programmatically before each run (`rows visible to the DO worker = 0`).
- **No `tryon_jobs` or `ai_jobs` were created by the load test**, because staging shares the production database and DO's worker would have claimed them and called the **paid** FASHN / image-gen providers. The write mix therefore uses only non-job-creating endpoints.
- All media generated locally (Pillow); no real user media touched.
- **Post-run residue: 0.** Totals returned to the Phase 3 baseline exactly — `wardrobe_items=28`, `auth.users=27`.
- **Total paid provider spend across all of Phase 5: 1 FASHN call (~$0.075)**, incurred during the credit-integrity test when DO's worker claimed a job in the ~1 s window before deletion. Disclosed rather than hidden; no bulk paid calls at any point.

Production was polled throughout and never degraded: `api.wearthemood.com/v1/health` returned 200 on every check, all four droplet containers stayed up, and DB backends held flat at **24/60**.

---

## 2. API load test (§14.2)

`k6` against `wtm-api-staging` → US Supabase. **194,636 requests over ~30 minutes at 106.4 RPS achieved.**

### A measurement correction that matters

Raw k6 numbers looked like a failure (read p95 **3.28 s**). They are not the server's latency: **minimum** observed latency was 262 ms, and the load generator runs from Bangladesh against a US dyno. Roughly 250–280 ms of client network RTT is baked into every sample.

The authoritative figure is Heroku's router `service=` time, which measures in-dyno processing and excludes client network. Both are reported below; the gates are assessed on server-side time.

| Gate | Target | Server-side (router) | End-to-end (k6, from Bangladesh) | Verdict |
|---|---|---|---|---|
| read p95 | < 600 ms | **52 ms** | 3.28 s | ✅ **PASS** (11× headroom) |
| write p95 | < 900 ms | **67 ms** | 2.80 s | ✅ **PASS** (13× headroom) |
| error rate | < 0.5 % | **0.00000 %** (0 non-2xx of 149,492) | 0.0005 % (1 client timeout of 194,636) | ✅ **PASS** |
| dyno memory | < 430 MB | **80.0 MB peak** (RSS 76.5 MB, swap 0) | — | ✅ **PASS** (5× headroom) |
| Heroku R14/R15 | zero | **0** (also 0 × H12/H13) | — | ✅ **PASS** |
| DB pool exhaustion | 0 | **0** — no pool/connection errors in app logs | — | ✅ **PASS** |
| DB connections | < 70 % of limit | **24 / 60 = 40 %**, flat throughout | — | ✅ **PASS** |
| no credit/refund duplication | required | see §2.2 | — | ✅ **PASS** |
| sustained rate | 120 RPS | **106.4 RPS achieved** | — | ⚠️ **client-limited** |

Per-endpoint server-side p95: `/v1/wardrobe` 59 ms · `/v1/news` 52 ms · `/v1/credits` 70 ms · `/v1/profile` 78 ms · `/v1/social/feed` 48 ms · `/v1/me` 19 ms · `/v1/outfits` 56 ms.

**On the 120 RPS shortfall:** k6 reported `Insufficient VUs, reached 300 active VUs` with 16,563 dropped iterations, and sustained only 478 kB/s of download — the generator's uplink, not the dyno, was the constraint. The server was nowhere near saturated at 106 RPS (52 ms p95, 80 MB RAM, zero errors), so this is a **test-harness limitation, not a capacity finding**. A confirmation run at 120 RPS from a US-based generator is recommended in the Phase 6 preflight. Per blueprint §14.2, no capacity claim beyond the measured 106.4 RPS is made here.

### 2.2 Credit / refund duplication

Two complementary tests on the real endpoint with a shared `Idempotency-Key`:

| Scenario | Result |
|---|---|
| **12 simultaneous** `POST /v1/tryon`, one shared key | `1 × 202` + `11 × 409` — exactly **1 job**, exactly **1 credit transaction** |
| **Sequential replay** of the same key ×2 after completion | both returned `202` with the **identical stored `job_id`**; credit delta stayed **1** |

Verdict **PASS**: no double-charge under either concurrency or replay. Note the first version of this test reported a false PASS — all 12 requests had 500'd and the assertion counted "zero duplicates" as success. The assertion was corrected so a 5xx can never satisfy the gate, and the underlying cause is recorded as a defect below.

### 2.3 Defect found — 500 on an unfetchable image URL

Submitting a `person_image_url` the moderation provider cannot download raises `openai.BadRequestError` inside `_moderate_inputs` (`app/routers/v1/tryon.py:83`) and propagates unhandled, returning **HTTP 500**. Per blueprint §13 the contract requires a typed error (`VALIDATION_ERROR` / `MODERATION_BLOCKED`), and a client-supplied bad URL is a user error, not a server fault. **Not fixed in Phase 5** (Phase 5 is measurement, not refactor); logged for the Phase 6 preflight backlog.

---

## 3. Worker tests (§14.3)

Isolation from the live DO worker used the Phase 4 technique: rows inserted as `'processing'` with a ~10 s-old lease are invisible to DO's `'queued'`-only claim, and Azure's `WORKER_STALE_SECONDS` was temporarily lowered to claim them (**reverted to 300 s afterwards, verified**). Attribution is positive: migration 0044's claim increments `attempt_count`; the pre-Phase-2 code on DO does not.

| Gate | Target | Measured | Verdict |
|---|---|---|---|
| sustained rembg throughput | ≥ 15 jobs/min | **15.0/min cold wave, 37.6/min warm wave** | ✅ PASS |
| warm queue wait p95 | < 20 s | **19.7 s** (enqueue → claim, 6-job batch) | ✅ PASS (tight) |
| cold queue wait p95 | < 90 s | **44.3 s** single-job pickup (Phase 4, same infra) | ✅ PASS |
| 100-job burst drained | < 10 min | **153 s (2.6 min)**, 100/100 completed, 0 failed | ✅ PASS |
| zero duplicate output | required | **100/100, 30/30, 30/30 distinct `cutout_url`** | ✅ PASS |
| zero duplicate refund | required | covered by §2.2 — single charge under concurrency | ✅ PASS |
| poison job terminates | required | seeded `attempt_count=99` → `failed` / `max_attempts`, no loop | ✅ PASS |
| max replicas | never > 3 | **3** observed peak across every run | ✅ PASS |
| replica-kill recovery | required | **deferred — see below** | ⚠️ deferred |
| recovery re-signals lost wake-up | required | **inconclusive — see below** | ⚠️ inconclusive |
| both worker types independently | required | rembg above; orchestrator proven via the enrichment leg (embedding written) | ✅ PASS |

**Measurement note.** A 30-job burst was first reported as failing the cold/warm gates (115.8 s / 36.1 s). That measured enqueue → **completion**, which on a 30-job burst across 3 replicas is dominated by burst depth, not platform pickup latency. The gate wording is queue **wait**, so it was re-measured as enqueue → **claim** (detected by the `attempt_count` increment). Both figures are reported above rather than only the flattering one.

**Two honest deferrals, both caused by the DO bridge — not by the platform:**

1. **Recovery re-signal is inconclusive.** Making a row recoverable requires ageing its lease past ~300 s, but that also ages it past DO's **120 s** `requeue_stale` threshold, so DO recovers it first. The test row came back `done` with `attempt_count` **0 → 0** — the DO signature, not Azure's. The recovery *job itself* executes correctly (`Succeeded`, confirmed on three separate executions), but end-to-end re-signal attribution cannot be proven while DO is live.
2. **Replica-kill recovery is deferred** for the identical reason: a killed Azure replica leaves a `processing` row that DO's 120 s requeue reclaims, making the result ambiguous.

Both must be verified in the Phase 6 preflight **after the DO worker is stopped**. This is the same overlap hazard already recorded as binding: **DO's 120 s requeue is shorter than Azure's 300 s lease, so the two worker planes must never run cutouts concurrently.**

**Harness defect worth recording.** An early burst attempt used a "lease keeper" that re-stamped `updated_at` on all in-flight rows every 30 s. Its bulk `UPDATE` held row locks, and `claim_cutout` uses `for update skip locked`, so claims were skipped, the worker (correctly) deleted those wake signals as stale no-ops, and **52 of 100 jobs were silently orphaned**. That was the test harness fighting the product, not a worker bug — but it does confirm a real design property: **a claim skipped under lock contention drops its wake signal, and only the recovery task heals it.** That makes enabling the recovery schedule at Phase 6 important rather than optional.

---

## 4. Cron tests (§14.4)

All six jobs executed manually via `az containerapp job start` (schedules remain on the never-firing `0 0 31 2 *`; DO's ofelia still owns cron).

| Job | Execution | Status | Notes |
|---|---|---|---|
| news | `wtm-prod-cron-news-fs484gt` | ✅ Succeeded | |
| daily-push | `wtm-prod-cron-daily-push-9zfus3g` | ✅ Succeeded | see safety note |
| backup | `wtm-prod-cron-backup-mjw3wiq` | ✅ Succeeded | **proves the direct DSN works from Azure** |
| spend-alert | `…-iaftyem` **and** `…-0irpv8m` | ✅ Succeeded ×2 | idempotency re-run |
| credit-reset | `…-08v6zq0` **and** `…-jv399eb` | ✅ Succeeded ×2 | idempotency re-run |
| giveaway-chats | `wtm-prod-cron-giveaway-chats-c24i37r` | ✅ Succeeded | |

- **Correct exit codes:** 6/6 `Succeeded`, plus 2 idempotency re-runs.
- **Idempotency / no duplicate effects:** `credit-reset` run twice reported `granted 0 subscription(s) for the current period` on the second pass — no double grant. `spend-alert` is read-only by construction.
- **Timeout:** every execution finished far inside `replicaTimeout` (1800 s); longest was backup at well under the limit.
- **`daily-push` safety.** This job sends **real push notifications to real users**, so it was not run blindly. `daily_push_hour` defaults to **8** and all 68 profiles are on `UTC`; execution was deliberately timed at **06:38 UTC**, making the recipient set provably empty. It validated the job path (startup, DB access, exit code) with **zero notifications sent to real devices**.

---

## 5. Cost extrapolation (§14.5) — **GATE FAILS at the 30k MAU target**

Measured unit cost, warm steady state: **4.8 replica-seconds per job** (30 jobs / 48 s / 3 replicas) = **9.6 vCPU-s + 19.2 GiB-s per job** at the locked 2 vCPU / 4 GiB sizing.

ACA Consumption rates used: $0.000024/vCPU-s, $0.000003/GiB-s, with the monthly free grant of 180,000 vCPU-s + 360,000 GiB-s. Queue operations at 30k MAU ≈ 180,000/month ≈ **$0.007** (negligible). Log Analytics at 30-day retention stays inside the 5 GB/month free ingestion tier ≈ **$0**.

### The structural problem

ACA bills **allocated** resources for as long as a replica is alive, including the scale-down `cooldownPeriod`. The moment the mean job arrival gap becomes shorter than the cooldown, the replica **never scales down** and is billed continuously:

| Load | Arrival gap | cooldown 600 s (as deployed) | after correction (60 s) |
|---|---|---|---|
| beta (~20 jobs/day) | 4,320 s | **$16.37/mo** | **$0.00/mo** ✅ |
| growth (~300 jobs/day) | 288 s | **$150.12/mo** (pinned on) | **$29.59/mo** |
| 30k MAU (~1,500 jobs/day) | 58 s | **$150.12/mo** (pinned on) | **$150.12/mo** (still pinned) |
| 100-job burst day | — | $14.90/mo | **$0.00/mo** ✅ |

Cost at 30k MAU versus cooldown, holding everything else fixed:

| cooldown | 600 s | 300 s | 120 s | 60 s | 30 s | 15 s | pure work, no idle |
|---|---|---|---|---|---|---|---|
| $/month | 150.12 | 150.12 | 150.12 | 150.12 | 88.56 | 48.06 | **7.56** |

The **actual compute** at 30k MAU is only **$7.56/month — comfortably inside the $10–12 target**. The entire overage is idle-but-billed time. The architecture is sound; the scale-down granularity is not.

### Verdict against the blueprint's flags

- Target Azure burn ≤ $10–12/month → **beta now $0.00 ✅**, 30k MAU **$150 ❌**
- Hard six-month average ceiling $16.67/month → **breached ~9× at the 30k MAU target ❌**
- Month-one projected pace > $20 = NO-GO → month-one is beta load: **$16.37 as-deployed, $0.00 after correction — NOT a NO-GO ✅**

**So Phase 6 is not blocked on month-one economics, but the 30k MAU target is not currently affordable on this configuration.**

### §14.6 fail-ladder action taken

Applied the free, non-paid correction: **`cooldownPeriod` 600 s → 60 s** on both workers, parameterised in `infra/azure/main.bicep` as `cooldownSeconds` so IaC and the live resources agree. Both apps re-verified `Healthy`/`Provisioned` afterwards; queues drained; max-replica limit untouched at 3. This alone takes beta and burst-day cost to **$0.00/month**.

Remaining options for the 30k MAU horizon are **not executed** — §14.6 requires approval for paid escalation, and the rest are architectural:

1. Cut worker sizing (2 vCPU/4 GiB → 1 vCPU/2 GiB) if rembg fits — roughly halves the rate.
2. Raise `queueLength` per replica so one replica absorbs more jobs before a second starts.
3. Increase per-replica batch/parallelism so 4.8 replica-s/job falls.
4. Reduce image dimensions / processing overhead (§14.6 step 7).
5. Paid escalation — different worker sizing or a dedicated plan (**requires founder approval**).

**Recommendation:** ship Phase 6 on current beta economics ($0/month, well inside every gate) and treat worker sizing/packing as a funded workstream before marketing pushes volume past roughly 300 jobs/day, which is where cost crosses the ceiling.

---

## 6. Tests and scans

- Backend suite: **627 passed** (unchanged; no application code was modified in Phase 5).
- Secret scan over tracked files: clean — no credential values in any committed file.
- Repo changes this phase: `infra/azure/main.bicep` (cooldown parameterised) + this report + state update.
- Test harnesses live in the scratchpad, outside the repo; the Cloudflare credential supplied earlier was cleared and never stored.

---

## 7. State after Phase 5

**Production is unchanged.** `api.wearthemood.com` → 200, `/r/*` → 302, all four droplet containers healthy (14 h uptime), no DNS, webhook, or droplet configuration touched. Azure remains **not routed**: 14 resources, workers at 0 replicas between tests, all seven jobs still on `0 0 31 2 *`, queues drained to 0. Heroku unchanged at Basic ×1 + Eco ×1 + Eco ×1 = **$12/month**.

Carried forward to Phase 6 preflight:

1. **Founder decision on 30k MAU worker economics** (§5) — the one gate that fails.
2. Replica-kill and recovery re-signal verification **after the DO worker is stopped** (§3).
3. 120 RPS confirmation from a US-based load generator (§2).
4. Fix the 500-on-unfetchable-image-URL contract violation (§2.3).
5. Cloudflare Pages candidate deploy — still binding from Phase 4.


---

# AMENDMENT — Phase 5 reopened (architecture change + remediation)

Phase 5 was **not approved** on the first pass, for three stated reasons: the 30k-MAU
Azure cost gate failed structurally, the API test never demonstrated 120 sustained
RPS, and an unfetchable `person_image_url` still returned HTTP 500. All three were
remediated under the approved architecture amendment.

## A1. Architecture: always-on Container Apps → event-driven Container Apps JOBS

The always-on design billed allocated resources for as long as a replica lived, so
any arrival gap shorter than the cooldown pinned a 2 vCPU / 4 GiB replica on
permanently (~$150/month vs a $16.67 ceiling). Jobs bill **per execution**.

| Resource | Trigger | Size | Scale |
|---|---|---|---|
| `wtm-rembg-job` | `jobs` queue | 2 vCPU / 4 GiB | min 0, **max 3**, poll 5s, parallelism 1, completion 1, retry 1, timeout 600s |
| `wtm-ai-orchestrator-job` | `enrichment` queue | 0.5 vCPU / 1 GiB | identical |

Unchanged: Postgres remains the source of truth, the queue is a wake signal only,
claims stay exact-job under `for update skip locked`, deductions/refunds/outputs stay
duplicate-safe, attempt+lease recovery is intact, and both Jobs reuse the **same**
user-assigned identity and the **same** least-privilege Storage Queue Data Contributor
assignment — no new identity, no widened scope.

The obsolete worker Container Apps were removed from IaC **and deleted from Azure**.
That was not merely cleanup: an attempt to neutralise them by repointing the KEDA
scale rule at a dummy queue only changed *scaling* — the container still read
`AZURE_QUEUE_JOBS` and kept consuming real messages — and the next full template
deployment silently reverted the rule. They stole every test signal, could not claim
the short-lease test rows, deleted those signals as unclaimable, and the orphans were
rescued by the DigitalOcean worker at its 120s requeue. That is why early Jobs runs
showed **0 attributed work while reporting `Succeeded`**. After deletion, attribution
is correct.

## A2. Finite batch entrypoints (§B)

`app.workers.rembg_batch` / `app.workers.orchestrator_batch` drain a bounded batch and
**terminate** — an endless loop would be billed exactly like the always-on App it
replaced. Limits are env-tunable: `REMBG_BATCH_MAX_JOBS=50`,
`ORCHESTRATOR_BATCH_MAX_JOBS=100`, `BATCH_MAX_SECONDS=420`, `BATCH_IDLE_EXIT_SECONDS=10`.
The time budget is checked between polls, never mid-job. A failing poll is counted and
retried rather than aborting the batch.

**Defect found and fixed during this work:** a batch that errored on *every* poll and
processed nothing returned 0, so Azure reported the execution `Succeeded`. That masked
a fully broken execution as healthy and cost real diagnosis time. Errors-with-no-progress
now exits non-zero. 11 tests cover every exit condition.

## A3. Cold-start optimization pass (no paid services added)

| Component | Measured |
|---|---|
| KEDA poll detect | ≤ **5 s** (was 15 s) |
| Image pull + scheduling | **~50 s** |
| Interpreter + ONNX model load (`startup_s`) | **43.2 – 46.0 s** |
| Per-image processing (`avg_job`) | **2.70 – 6.13 s** |
| Orchestrator startup (no model) | **1.2 s** |
| Image size | **1.57 GB → 1.49 GB** |
| Model | `/models/u2net.onnx`, **176 MB, baked and build-time asserted, never fetched at runtime** |

Also dropped `PYTHONDONTWRITEBYTECODE` and pre-compiled bytecode: that flag saves image
size but forces recompiling the whole dependency tree on every cold start — backwards
for a Job that always cold-starts.

**This reframes the problem.** ONNX session init (~43 s) plus image pull (~50 s) is
essentially all of the ~100 s activation. Trimming 80 MB of layers and 10 s of polling
cannot move the gate much; the only remaining lever is a smaller/faster model
(ISNet / quantized U2Net). No paid Azure Container Registry was created.

## A4. Revised worker gates — measured after tuning

| Gate | Target | Measured | Verdict |
|---|---|---|---|
| Activation p95 (steady, 10-job waves) | ≤ 120 s | **98.9 – 105.4 s** | ✅ |
| Activation p95 (100-job burst) | hard < 150 s | **140.6 s** | ✅ hard gate (target exceeded under burst) |
| End-to-end p95 | < 180 s | **104.2 – 140.6 s** | ✅ |
| 100-job burst drain | < 10 min | **149 s (2.5 min)**, 100/100 | ✅ |
| Sustained throughput | ≥ 15 jobs/min | **40.4 jobs/min** | ✅ |
| Max concurrent executions | ≤ 3 | **3** (cap hit exactly, never exceeded) | ✅ |
| Zero duplicate outputs | required | **100/100 distinct `cutout_url`** | ✅ |
| Poison job terminates | required | `failed` / `max_attempts` | ✅ |
| Truthful exit | required | `errors=0 reason=idle`, all `Succeeded`; all-fail now exits non-zero | ✅ |

*Attribution note:* the burst reported 36/100 Azure-attributed only because the sampler
polls every 2 s and 100 rows churn faster than that — all 100 completed with distinct
URLs across 3 `Succeeded` executions. Steady-state waves attributed 7/10 and 10/10.

## A5. Cost — from measured execution data, not estimates

Using the measured `startup_s = 43.2 s` and `avg_job = 4.0 s` at batch 50:

| Load | vCPU-s/mo | GiB-s/mo | Cost |
|---|---|---|---|
| beta (~20 jobs/day) | 2,957 | 5,914 | **$0.00** |
| growth (~300/day) | 87,552 | 175,104 | **$0.00** |
| **30k MAU (~1500/day)** | **437,760** | **875,520** | **$7.73/mo** |

Queue ops ≈ $0.007/mo; Log Analytics inside the 5 GB free tier. Orchestrator adds ~1.2 s
startup at 0.5 vCPU and stays inside the free grant.

**$7.73/mo — inside the $16.67 hard ceiling and the $12 preferred target.** ✅

## A6. Invalid-input contract (§F)

An unfetchable/invalid `person_image_url` now returns the documented typed
**`VALIDATION_ERROR` (422)**, never an unhandled 500. A moderation-provider outage
returns **`PROVIDER_ERROR` (503)** and deliberately fails **closed** — §19 makes input
moderation mandatory, so a moderator that cannot answer must block the job rather than
let an unchecked image through. Four regression tests.

## A7. Client UX for slow starts

Activation is legitimately ~100 s, so the client must not read that as failure:

- **0–45 s** — normal "Removing background" state.
- **After 45 s** — "Still preparing your item — you can safely leave this screen".
  Never a failure, and polling continues.
- **App resume** short-circuits the poll wait so work finished in the background is
  picked up immediately.
- **Hard cap 3 minutes**, valid only while measured end-to-end p95 stays < 180 s (it is,
  at 104–141 s). If that regresses, raise the cap rather than show a false error.
- **6 regression tests** assert a job unfinished at 45 / 90 / 179 s is never marked failed.

The pre-existing client actually used a 90 s cap (not the 45 s/3 min described), and on
timeout already avoided showing failure; the cap was raised and the reassurance state added.

---

# CLOSE-OUT — launch-readiness gates verified, scale optimization deferred

Phase 5 is closed against **launch-readiness** criteria: the migration must land safely
with a fully working application. It is explicitly **not** a certification of 30k-MAU
enterprise capacity. Headroom work that is not required to launch is recorded below as
deferred, with the evidence that justifies deferring it rather than as an open unknown.

## E1. The 120 RPS gate — now measured properly, and it PASSES

The earlier caveat ("106.4 RPS achieved, client-limited") is **resolved, not deferred.**
Re-run from a GitHub-hosted runner in **Chicago, Illinois (Azure `northcentralus`,
AS8075)** — co-located with the US dyno, which removes the ~250–280 ms Bangladesh RTT
that previously sat inside every sample.

**Run `29697233690` · 2026-07-19 17:38:51 → 18:08:52 UTC · 30m00.0s.**

| Gate | Target | Measured | Verdict |
|---|---|---|---|
| sustained rate | 120 RPS | **119.997 RPS** (216,000 reqs in exactly 30m00.0s) | ✅ **PASS** |
| dropped iterations | 0 | **0** | ✅ PASS |
| error rate | < 0.5 % | **0.00 %** — 0 failures of 216,000 | ✅ PASS |
| read p95 | < 600 ms | **47.28 ms** (p99 54.26 ms) | ✅ PASS (12.7× headroom) |
| write p95 | < 900 ms | **42.55 ms** (p99 48.24 ms) | ✅ PASS (21× headroom) |
| generator headroom | — | **14 of 1,500 VUs used** | harness was never the constraint |

Overall: med 32.24 ms, p95 46.94 ms, max 1.03 s, 1.0 GB received at 558 kB/s.

Two things make this measurement trustworthy where the first was not. A **preflight**
asserts the synthetic identities actually authenticate (`/v1/me` → 200 on 5 sampled of
40) — without it, an expired token set produces a run where every request 401s, the RPS
looks perfect and the result is meaningless. And the generator peaked at **14 of 1,500
pre-allocated VUs**, so the achieved rate is a statement about the server, not about the
load generator. These are end-to-end client numbers, not router `service=` times: the
earlier report had to fall back to server-side timing to be honest, and no longer does.

**No deferral is claimed here.** The load gate passed at the full target rate.

## E2. Launch-readiness gates

| # | Gate | Evidence | Verdict |
|---|---|---|---|
| 1 | Heroku candidate API healthy, no crash | 216,000 requests / 0 failures / 0 restarts; `/readyz` 200 before and after | ✅ |
| 2 | Supabase US DB connections correct | `/readyz` → `db:true` on prod **and** staging, both `commit 17a3a8c`, against `aws-0-us-east-1.pooler…:5432` | ✅ |
| 3 | Azure Jobs process normal synthetic work | 100/100 burst drained in 149 s at 40.4 jobs/min; every recent execution `Succeeded` | ✅ |
| 4 | No duplicate output / credit / refund | 12 concurrent same-key → `1×202 + 11×409`, 1 job / 1 charge; 100/100 distinct `cutout_url` | ✅ |
| 5 | Failed jobs terminate truthfully | poison job → `failed`/`max_attempts`; an all-error batch now **exits non-zero** instead of reporting `Succeeded` | ✅ |
| 6 | Projected cost within launch budget | **$12/mo at launch** (Heroku $12 + Azure $0 + Supabase free); $19.73/mo at 30k MAU | ✅ |
| 7 | Flutter bg-removal never shows false failure | reassurance state at 45 s, 3-min cap, resume short-circuit; 6 regression tests assert a job unfinished at 45/90/179 s is never marked failed | ✅ |
| 8 | DigitalOcean production untouched | `api.wearthemood.com/v1/health` → 200, `/r/*` → 302, verified again after cleanup | ✅ |
| 9 | Test data and queues clean | see E3 — back to the exact Phase 3 baseline | ✅ |
| 10 | Documentation updated | this report, `MIGRATION_STATE.md`, `OPS_RUNBOOK.md` §5.2–5.4 | ✅ |

## E3. Test-data teardown (gate 9) — residue found and removed

The §E runs were **not** self-cleaning: the k6 write mix includes `POST /v1/outfits` at
~2 %, so ~4.3k rows accumulated in the authoritative US project. Audited before deleting
anything, then removed under three guards (test domain only, known synthetic prefixes
only, abort unless totals land on the Phase 3 baseline).

| Object | Removed |
|---|---|
| `auth.users` (48: 47 `wtm-p5-load*` + 1 `wtm-p5diag*`, all `@wtm-migration-test.invalid`) | 48 (all `200`) |
| `outfits` | 4,383 |
| `wardrobe_items` | 553 |
| `profiles` / `credits` / `ai_usage_log` | 47 / 46 / 3 |

**The safety result that matters:** marker-named rows owned by a **real** user =
**0** across `wardrobe_items`, `outfits` and `profiles.display_name`. The load test wrote
only to accounts it created; no production row was mutated.

Final state — `auth.users` **27**, `wardrobe_items` **28**: *exactly* the Phase 3
baseline. `outfits` 7 (all real). Zero rows on the test domain, zero marker rows. Every
`wardrobe_item` is `cutout_status='done'`, so nothing is claimable by the still-live DO
worker; no `tryon_jobs`/`ai_jobs` pending. Supabase Storage was never written by the
harness (DB-only), so object counts are unchanged.

Azure side: both queues drained — the last execution of either Job was 16:25 UTC on
2026-07-19 and **none has fired since**, which with a 5 s KEDA poll means the queues are
empty. The obsolete always-on worker Apps are confirmed **deleted**; only
`wtm-prod-api-emergency` remains, at **0 replicas** (min 0 / max 1, guarded off, $0). All
seven scheduled Jobs remain on `0 0 31 2 *` — DO's ofelia still owns cron.

## E4. Deferred to post-cutover (does not block migration)

1. **Background-removal cold start (~100 s activation).** Accepted for launch. ONNX
   session init (~43 s) plus image pull (~50 s) is essentially all of it, so the only
   remaining lever is a smaller/faster model (ISNet / quantized U2Net). **Deliberately
   not attempted now** — changing the bg-removal model is a quality decision that must be
   validated on real devices with real garments, not tuned against synthetic load. The
   client already treats this latency honestly (gate 7), so it is a cost/UX optimization,
   not a correctness problem. **Evaluate through real-device testing after cutover.**
2. **30k-MAU worker sizing/packing.** At $7.73/mo the current configuration is inside
   the $16.67 ceiling, so this is headroom tuning, not a blocker. Revisit if sustained
   volume approaches ~1,500 jobs/day.
3. **Replica-kill and recovery re-signal attribution** — still genuinely unproven, and
   still **binding for Phase 6**. These cannot be measured while the DO worker is live
   (its 120 s requeue beats Azure's 300 s lease), so they must run after the DO worker
   stops and before `AUTHORIZE DNS CUTOVER`. This is the one item in this list that is a
   real gate rather than an optimization.
4. **Pre-existing `ruff format` drift** on the backend (61 files, inherited from `main`,
   unrelated to the migration). `ruff check` is clean; a one-time `ruff format .` should
   land as its own commit rather than inside a migration change.

## E5. Verification performed at close-out

`ruff check` clean · **641 backend tests passed** (was 627; +14 from the remediation) ·
Heroku prod + staging `/readyz` 200 `db:true` · DO production 200/302 · Azure inventory
and execution history as described · residue audit + teardown verified against the
baseline. One lint regression introduced by the Phase 5 remediation
(`E501` in `app/core/config.py:59`) was fixed here; it had turned `migration-build` red.

## Result

**PHASE 5 COMPLETE — launch-readiness gates verified, scale optimization deferred.**
Production and DNS untouched. Azure still not routed. Phase 6 not started.

## Next approval phrase

```
APPROVED PHASE 5
```
