# PHASE 5 REPORT — load, throughput, failure, and cost gates

**Objective:** prove the six-month architecture against the 25–30k MAU launch target before production routing.

**Starting commit:** `b3741b9` · **Ending commit:** this commit.
**Result:** ⚠️ **Performance gates PASS with large headroom. The COST gate FAILS at the 30k MAU target** — a structural Azure Container Apps billing issue, not an application defect. Beta-load cost was corrected to $0/month. A founder decision is required before Phase 6.

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

## Next approval phrase

```
APPROVED PHASE 5
```
