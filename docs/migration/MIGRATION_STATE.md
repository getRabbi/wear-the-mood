# MIGRATION STATE — Wear The Mood → Heroku + Azure + Supabase US

> Live state tracker for the infrastructure migration. Updated at the end of every phase.
> Authoritative plan: `WEAR_THE_MOOD_INFRASTRUCTURE_MIGRATION_BLUEPRINT_FINAL.md` (repo root, input document only — not committed).
> No secret values appear in this file. Secret **names** only, where needed.

---

## Current position

| Field | Value |
|---|---|
| Working branch | `migration/heroku-azure` |
| Base commit (`origin/main`) | `98df3c359ff711d4949e27b7ac2de4528602829b` |
| Current phase | **Phase 5 complete — HARD STOP at Gate 5** (perf gates PASS; COST gate fails at 30k MAU) |
| Last completed | Phase 5 — load / throughput / failure / cost gates measured |
| DigitalOcean role | **LIVE PRODUCTION on the US DB** (api+worker+ofelia repointed to `us-east-1`) — bridge until Phase 6 compute cutover + 48h soak. **Untouched by Phase 4.** |
| Authoritative DB | **Supabase US `ghzabbceoaoertatkjyg` (us-east-1)** — Tokyo retained as cold backup (do NOT delete) |
| Next human approval phrase | `APPROVED PHASE 5` |

---

## Phase gate tracker

| Phase | Description | Status | Gate phrase |
|---|---|---|---|
| Bootstrap | Branch + state files | ✅ complete | — |
| 0 | Read-only discovery | ✅ approved | `APPROVED PHASE 0` |
| 1 | Encrypted backup + restore proof | ✅ approved | `APPROVED PHASE 1` |
| 2 | Code refactor + reproducible IaC (DO unchanged) | ✅ approved | `APPROVED PHASE 2` |
| 3 | Supabase Tokyo → us-east-1 migration | ✅ approved | `APPROVED PHASE 3` |
| 4 | Provision Heroku + Azure, deploy candidates (not routed) | ✅ **approved** — one item formally deferred (see binding condition below) | `APPROVED PHASE 4` |
| 5 | Load / throughput / failure / cost gates | ⚠️ complete — awaiting gate (perf PASS, **cost gate fails at 30k MAU**) | `APPROVED PHASE 5` |
| 6 | Production cutover + 48h soak | ⛔ not started | `APPROVED PHASE 6` |
| 7 | DigitalOcean decommission | ⛔ not started | — (PR + human review) |

Second-authorization phrases required inside specific phases (not a substitute for the gate):
`AUTHORIZE DO SNAPSHOT` (P1) · `AUTHORIZE SUPABASE CUTOVER` (P3) · `AUTHORIZE DNS CUTOVER` (P6) · `AUTHORIZE DIGITALOCEAN DECOMMISSION` (P7).

---

## Bootstrap verification (completed)

Prerequisites confirmed for the current phase (later-phase tools audited in their own phases):

| Check | Result |
|---|---|
| Repository root | `E:/dopplefit` |
| `origin` remote | `getRabbi/wear-the-mood` |
| `origin/main` SHA | `98df3c359ff711d4949e27b7ac2de4528602829b` (matches locked base) |
| Working tree | clean (blueprint input doc locally excluded via `.git/info/exclude`) |
| Blueprint readable | yes |
| DigitalOcean SSH (`root@159.65.248.247`, host `fashion-os`) | reachable, read-only OK |
| Docker daemon | Docker Desktop, `linux/amd64` engine responding |
| GitHub (`gh`) | authenticated as `getRabbi`; scopes include `repo`, `workflow`, `write:packages` |
| Heroku | authenticated (`wearthemood24@gmail.com`) |
| Azure (`az`) | `Azure for Students`, Enabled, subscription `…b5cc` |

---

## Confirmed operating decisions

- Heroku production API and the DigitalOcean bridge use the Supabase **Session Pooler on port 5432**.
- Use **direct DB access** for backup when reachable; **Session Pooler 5432** is the IPv4 fallback.
- Do **not** switch runtime to Transaction Pooler 6543 unless Phase 0 finds a concrete requirement.
- Heroku and Azure authentication are already active.
- The human handles: browser approval, MFA, GPG passphrase, Supabase project-creation confirmation, DNS cutover authorization, and final resource-deletion authorization.

---

## Locked cost guards (from blueprint §3.4)

- GHCR is the canonical registry (no Azure Container Registry). No Azure VM/DB/Redis/Service Bus/Front Door/API Management.
- Azure: Storage **Queue** only (Standard_LRS), Container Apps **Consumption** only; Log Analytics ≤ 30-day retention if required.
- Heroku prod: exactly one **Basic** web dyno; staging on **Eco**; no paid add-ons.
- No Supabase Pro upgrade in this migration. No FASHN paid tier / auto top-up.

---

## ⛔ MANDATORY PHASE 6 PREFLIGHT — post-DO-shutdown recovery attribution

These CANNOT be proven while the DigitalOcean worker is live, because DO's
`requeue_stale` fires at **120s** while the Azure lease is **300s** — DO always
recovers a stale row first, so any result is attributed to DO, not Azure. Each was
attempted in Phase 5 and returned `attempt_count 0 -> 0`, the DO signature.

**Run all three AFTER the DO worker and ofelia are stopped, BEFORE `AUTHORIZE DNS CUTOVER`:**

1. **Replica-kill recovery attribution** — kill a `wtm-rembg-job` execution mid-batch;
   the claimed row must be re-claimed and completed by a later execution, with
   `attempt_count` incrementing (proving Azure, not DO, recovered it).
2. **Azure recovery re-signal attribution** — leave a claimable row with NO queue
   message; `wtm-prod-recovery` must re-signal it and an Azure execution must
   complete it with `attempt_count >= 1`.
3. **Overlap verification** — confirm the 120s DO stale-recovery window and the 300s
   Azure lease can never both be active. The two worker planes must never run
   cutouts concurrently; the cutover must stop the DO worker before Azure takes
   cutout traffic.

Until then these three gates are **explicitly unproven**, not passed.

## ✅ BINDING CONDITION SATISFIED — Cloudflare Pages candidate (was deferred from Phase 4)

The Phase 4 deferral is **closed**. The candidate was deployed and preview-verified on
2026-07-19 with a correctly-scoped token, **without touching production DNS**.

| Item | Value |
|---|---|
| Pages project | `wtm-site` · environment **preview**, branch `migration-candidate` |
| Preview URL | `https://migration-candidate.wtm-site.pages.dev` (immutable: `8939dac3.wtm-site.pages.dev`) |
| Custom domains attached | **`wtm-site.pages.dev` only — `wearthemood.com` NOT attached** |
| Token scope | Account · Pages only — `/user/tokens/verify` 403s while the Pages API succeeds, proving it cannot reach User or Zone endpoints (so it cannot alter DNS) |

Every required check passed: landing, all three legal pages, `/invite/`, `delete-account`,
`_headers` (content-type **and** cache rules), **`/.well-known/assetlinks.json` 200 `application/json`**,
**`/.well-known/apple-app-site-association` 200 `application/json` with no redirect**, and `/r/*`
(proven earlier against the Heroku candidate). Full detail in `PHASE_4_REPORT.md` §4.3.

**⚠ One delta carried into Phase 6:** Pages strips `.html` and 308-redirects to the canonical
extensionless URL, where the droplet serves `.html` directly at 200. Content is byte-correct
after the redirect and store crawlers follow 308s, but the published Privacy / Terms /
delete-account URLs should be updated to the extensionless form at cutover. `.well-known`
files are unaffected.

**Still binding for Phase 6:** production DNS remains unchanged until `AUTHORIZE DNS CUTOVER`.
The Pages token must NOT be reused for cutover work — that needs a separate **Zone · Read +
Zone · DNS · Edit** token, issued only when Phase 6 begins. The two earlier credentials (one
exposed in chat, one invalid) remain burned and must be revoked.

## Deployed target inventory (Phase 4 — candidates, NOT routed)

No secret values. Names, digests, and identifiers only.

| Item | Value |
|---|---|
| Heroku prod app / release | `wtm-api-prod` / **v4**, Basic ×1, container stack, US |
| Heroku staging app / release | `wtm-api-staging` / v35, **Eco ×1** (sleeps when idle) |
| Heroku admin app | `wtm-admin` — **Eco ×1**, US Common Runtime, container stack |
| Heroku admin URL / image | `https://wtm-admin-aab1ebe5235d.herokuapp.com` · `sha256:2627d4c41dab7dad13564aad8ceee53f1c705ab47767bd1d197583d01ea209c6` |
| Heroku API image digest (both APIs) | `sha256:e5d857da6fdcfa1232cbdb405b5a2583b5288de203ddb302c5497999583d002e` |
| Heroku cost | **$7 Basic + $5 account-wide Eco = $12/mo** (Eco = 1,000 h **shared** across both Eco apps, not per-app) |
| Cloudflare Pages candidate | `wtm-site` preview → `migration-candidate.wtm-site.pages.dev` (**no custom domain attached**) |
| Heroku prod custom domain | `api.wearthemood.com` → DNS target `synthetic-castle-h9xyrshjsxcexe5nwsld570w.herokudns.com` (**not applied to DNS**) |
| Azure resource group / region | `wtm-prod` / **`koreacentral`** (blueprint `eastus` blocked by subscription policy) |
| Azure deployment name | `wtm-prod-phase4` (Succeeded) |
| Storage account | **`wtmprodq4k2n8`** (Standard_LRS) · queues `jobs`, `enrichment` |
| Managed identity | `wtm-prod-id` · clientId `0f0b54aa-ebee-4a1c-b258-5c7d695aba6a` · principalId `5ba8e745-fb4b-4271-ba14-342e4d4f3df7` |
| RBAC | Storage Queue Data Contributor, scoped to the storage account only |
| Container Apps | `wtm-prod-rembg-worker` (2 vCPU/4 GiB, 0→3) · `wtm-prod-ai-orchestrator` (0.5/1 GiB, 0→3) · `wtm-prod-api-emergency` (0.5/1 GiB, 0→1, guarded off) |
| ACA Jobs | `wtm-prod-recovery` + 6 `wtm-prod-cron-*` — **all on `0 0 31 2 *` (never fire)** |
| Emergency FQDN (no route) | `wtm-prod-api-emergency.bravebay-86146722.koreacentral.azurecontainerapps.io` |
| GHCR `wtm-api` | `sha256:828461c932df07e3dbe595e03d17f585f22e5a4bafb764efe65408f54d7867f0` |
| GHCR `wtm-rembg-worker` | `sha256:6accc51d73b7e317dec3e47cb9a2ae7b73834eb72cf45027b097eae3b5552ea5` |
| GHCR `wtm-orchestrator` | `sha256:34147d22906168692b1febd00b04399479c862fb48174770fdef642b938c2a92` |
| Azure budget | `wtm-prod-monthly` — $100 base, alerts at $10/$25/$50/$75/$90 (+forecast $90) |

## Phase 0 headlines (full detail in `DISCOVERY.md`)

- **System:** 1 DO droplet (Ubuntu 24.04, 2 vCPU, 3.8 GiB), compose `fashionos` = `api`+`worker`+`admin-web`+`caddy`+`ofelia`. Supabase Tokyo **PG 17.6, 19 MB**. Media = **Supabase Storage** (120 objects / ~72 MB). No Redis/broker; DB-poll worker; claims use `SKIP LOCKED`; credits idempotent.
- **Tests:** backend `580 passed, 2 skipped` (local venv). CI red = **formatting only** (tests pass), pre-existing on main.
- **No hard blockers.** Amendments needing a Gate 0 decision:
  1. **(Major)** media is on Supabase Storage → Phase 3 migrates ~72 MB + rewrites legacy public URLs.
  2. **Admin console is ON the droplet** → propose Heroku Eco `wtm-admin`.
  3. **Static site + `/r/*` on droplet Caddy** → Cloudflare Pages + Heroku-API route.
  4. Phase-2 reliability: recovery + attempt/lease fields for `tryon_jobs`/`ai_jobs`; output-row uniqueness; external status mapping.
  5. Runtime DSN → **Session Pooler 5432** (no requirement forces 6543).
- **Cost impact of Phase 0:** zero (no cloud resource created).

## Phase 1 headlines

- **Complete encrypted backup taken + restore-verified.** One AES-256 GPG archive at `r2://fashionos-private/migration-backups/2026-07-18/wtm-phase1-backup-20260718.tar.gpg` (SHA `9b4f7b59…`): DB roles/schema/data (incl. auth + 12 password hashes), 120 Storage objects (76.5 MB), droplet config, git bundle.
- **Restore test PASS** — restored into a fresh local Supabase stack: 0 errors, all counts match source, FK integrity holds.
- DO snapshot `wtm-pre-migration-20260718` taken (live, droplet 577335646). Baseline tag `pre-migration-20260718` → `98df3c3` pushed. **Retention: keep all backups + snapshot through 2026-09-01.**
- Owner still to provide: DO snapshot **ID**; Cloudflare lifecycle confirmation on `fashionos-private`.

## Phase 2 headlines (full detail in `PHASE_2_REPORT.md`)

- **New deployable units built on-branch; DO unchanged.** 11 small commits: queue abstraction, migration `0044` (attempt/lease/signal/output-uniqueness), split `rembg_worker`/`ai_orchestrator` + `wtm-recovery`, `/healthz`+`/readyz`+maintenance+emergency guard, external status mapping, API enqueue-after-commit, `app.tasks.*` cron wrappers, 3 Dockerfiles, GitHub Actions (GHCR build + gated Heroku deploy), Azure Bicep, Cloudflare route plan.
- **Backend suite: 625 passed / 2 skipped** (+45). API image builds at 461 MB; Bicep compiles clean (13 resources); migration 0044 validated + idempotent. Secret scan clean.
- **Backward compatible:** legacy `status` kept (new `state` added), `/v1/health` kept, combined worker + `app.cron.*` + `docker-compose.yml` untouched. Migration 0044 NOT applied to Tokyo (applied to US project in Phase 3).
- **Follow-ups (non-blocking):** CI `ruff format --check` needs a one-time `ruff format .` (pre-existing drift); rembg model checksum-pin is a hardening TODO; Azure schedule jobs stay disabled until Phase 4.

## Phase 4 headlines (full detail in `PHASE_4_REPORT.md`)

- **Resumed after an interruption.** Recovery audit reconciled cloud/Git/Docker state first: Heroku apps + 2 of 3 GHCR images already existed (reused, not recreated); `wtm-rembg-worker` had never been pushed; Azure was completely empty. No ambiguous non-idempotent operation.
- **Heroku:** `wtm-api-prod` release **v4**, Basic ×1, 40 config vars, `/readyz` = `db:true, commit 17a3a8c`. `wtm-api-staging` v35, same immutable image digest, scaled to **0** after testing. `api.wearthemood.com` registered on the app (DNS target recorded) — **no DNS changed**.
- **Azure `wtm-prod` / `koreacentral`, 14 resources, deployment Succeeded.** Storage Queue only, UAMI + Storage Queue Data Contributor (least privilege), Consumption ACA, workers 0→3 on queue depth at the exact locked CPU/memory, emergency API guarded off, all 3 images pinned by **digest**, 12 ACA secret refs, private GHCR pull proven.
- **Two defects found + fixed:** (1) the six cron jobs were commented "disabled" but had **live schedules** — would have duplicated ofelia against production; now `0 0 31 2 *` behind `cronSchedulesEnabled=false`. (2) `DefaultAzureCredential` could not resolve the **user-assigned** identity — added `AZURE_CLIENT_ID` to `baseEnv`; queue auth now 200.
- **E2E proven with attribution.** A first run was silently handled by the **DO worker**; re-run isolated (insert as `processing` w/ stale lease) and confirmed Azure via `attempt_count=1`. Cold pickup **44.3 s** (gate <90 s), warm **2.9 s** (gate <20 s), duplicate signal = no-op, garbage drained, recovery job Succeeded, queues drain to 0, **94.6 vCPU-s / 189.2 GiB-s per job**. Zero test-data residue (totals back to 28 items / 27 users).
- **⚠ Phase 6 hazard found:** DO's `requeue_stale` is **120 s** but the Azure lease is **300 s** — concurrent planes would let DO requeue an item Azure is still processing. The DO worker must be stopped before Azure takes cutout traffic.
- **Cost:** Azure budget `wtm-prod-monthly` created **programmatically** ($100 base → alerts at exactly $10/$25/$50/$75/$90 + forecast). Azure MTD **$0**. Heroku **$12.00/mo** ≤ $13 gate.
- **Gate reopened + corrected (owner subscribed to Eco).** The first pass wrongly treated Eco as a per-app charge and rejected `wtm-admin` as +$7/mo. **Eco is one account-wide $5 plan with 1,000 dyno-hours shared across all personal Eco apps**, so a second Eco app is $0 marginal. Now: staging **Eco ×1**, `wtm-admin` created + deployed **Eco ×1** (rebuilt against **US** Supabase — closes the Phase 3 Tokyo follow-up; root 404s, unauthenticated `/dashboard` → 307 login, `noindex`). Approved allocation $7 + $5 = **$12/mo**.
- **Eco behaviour verified:** staging `up`→`idle` at 21:08:55Z (~30 min idle), wakes in **11.6 s** (`db:true`); admin confirmed idle, wakes in **7.9 s** with the auth gate intact. **No pingers** — no add-ons, no scheduled workflows, no `herokuapp.com` refs in code, none from the droplet. Pool at **998h 21m (99%)** remaining. Recorded in `OPS_RUNBOOK.md` §5.1.
- **`/r/*` verified on the Heroku candidate** — 302 → `https://wearthemood.com/`, identical to the live DO route, with no route change.
- **Cloudflare Pages still owner-gated:** the supplied token was rejected by every auth scheme (`1000`/`9109`/`10000`/`9103`) and was **cleared, not stored**; needs **Account · Cloudflare Pages · Edit** (no Zone/DNS scope). Prepared meanwhile: `deploy/site/_headers` pins `application/json` on `apple-app-site-association` (extensionless → Pages would serve `octet-stream` and silently break Universal Links).
- Tests **627 passed**; secret scan clean; repo changes: `infra/azure/main.bicep`, `deploy/site/_headers`, `OPS_RUNBOOK.md`.

## Phase 5 headlines (full detail in `PHASE_5_REPORT.md`)

- **Performance gates all PASS with large headroom.** 194,636 requests over ~30 min at 106.4 RPS: server-side **read p95 52 ms** (gate 600), **write p95 67 ms** (gate 900), **0.00000 % errors**, **peak dyno memory 80 MB** (gate 430), zero R14/R15, zero pool exhaustion, DB connections flat at **24/60 = 40 %** (gate <70 %).
- **Measurement correction:** raw k6 showed read p95 3.28 s, but minimum latency was 262 ms because the generator runs from Bangladesh against a US dyno. Heroku router `service=` time is the authoritative server-side metric. 120 RPS was not reached (106.4 achieved) — the generator's uplink was the limit, not the dyno; no capacity claim beyond the measured rate.
- **Credit/refund duplication PASS:** 12 concurrent same-key requests → `1×202 + 11×409`, exactly 1 job and 1 charge; sequential replay returns the identical stored `job_id`. (A first version reported a false PASS on 12×500s; the assertion was fixed so a 5xx can never pass.)
- **Worker gates PASS:** 100-job burst drained in **153 s** (gate <10 min), throughput 15.0–37.6 jobs/min (gate ≥15), warm queue wait p95 **19.7 s** (gate <20), cold pickup 44.3 s (gate <90), **zero duplicate output** across 160 jobs, poison job terminates as `failed`/`max_attempts`, **max replicas never exceeded 3**.
- **Cron: 6/6 executed manually and Succeeded**, incl. backup (proves the direct DSN works from Azure). `credit-reset` + `spend-alert` re-run → no duplicate effects. `daily-push` was deliberately timed at 06:38 UTC (all users UTC, push hour 8) so **zero real notifications** were sent.
- **⚠️ COST GATE FAILS at 30k MAU.** ACA bills allocated resources through the scale-down cooldown, so once the arrival gap drops below the cooldown the 2 vCPU/4 GiB replica is pinned on: **~$150/mo vs the $16.67 ceiling**. Actual compute is only **$7.56/mo** — the overage is entirely idle-but-billed time. Applied the free §14.6 correction (**cooldown 600 s → 60 s**, parameterised in Bicep): **beta and burst-day cost → $0.00/mo**, and **month-one is NOT a NO-GO**. Worker sizing/packing for 30k MAU needs a founder decision.
- **Two honest deferrals** (both caused by the DO bridge, not the platform): replica-kill recovery and recovery re-signal attribution can't be proven while DO's 120 s requeue beats Azure's 300 s lease — verify in Phase 6 after the DO worker stops.
- **Data safety:** 40 synthetic users / 480 items, all seeded `cutout_status='done'` so production could never claim them; **0 residue** (totals back to 28 items / 27 users). Total paid provider spend for the whole phase: **1 FASHN call (~$0.075)**, disclosed.
- New defect logged: unfetchable `person_image_url` → **500** instead of a typed `VALIDATION_ERROR` (§13 contract violation).

## Change log

- **Bootstrap** — created `migration/heroku-azure` from `origin/main@98df3c3`; created this file; verified current-phase prerequisites.
- **Phase 0** — read-only discovery complete; wrote `DISCOVERY.md`, `ENV_MATRIX.md`, `PHASE_0_REPORT.md`; no infra changes. **APPROVED PHASE 0** with binding clarifications (media backup = Supabase Storage; admin → Heroku Eco `wtm-admin`; static → CF Pages + `/r/*`→Heroku; runtime DSN = Session Pooler 5432; R2 = encrypted backups only).
- **Phase 1** — encrypted backup + restore proof complete; wrote `BACKUP_MANIFEST.md`, `ROLLBACK_RUNBOOK.md`, `PHASE_1_REPORT.md`. DO snapshot taken; encrypted archive uploaded to R2 + restore-verified. **APPROVED PHASE 1**.
- **Phase 2** — code refactor + reproducible IaC complete (11 commits, DO unchanged); wrote `PHASE_2_REPORT.md`. 625 tests pass; migration 0044 created (not applied to prod). **APPROVED PHASE 2** (media→Storage; admin→Heroku Eco; static→CF Pages; DSN=Session Pooler 5432; R2=backups only).
- **Phase 3** — Tokyo → us-east-1 cutover COMPLETE + verified (US `ghzabbceoaoertatkjyg`). DB restored (all counts match, 0044 applied, FK ok), 120/120 Storage objects migrated, 143 URL rows rewritten, DO bridge repointed to US (Session Pooler 5432), smoke PASS. Tokyo retained cold. **Rollback boundary crossed.** Wrote `PHASE_3_REPORT.md` + `HUMAN_HANDOFF.md`. Pending: owner encrypts final dump; auth-provider config on US; admin-web rebuild. **APPROVED PHASE 3**.
- **Phase 4** — resumed after interruption (recovery audit first, nothing duplicated). Pushed the missing `wtm-rembg-worker` image; released the same immutable API artifact to Heroku staging + prod (prod v4, Basic ×1, `db:true`); registered `api.wearthemood.com` without touching DNS; deployed Azure `wtm-prod` in **`koreacentral`** (14 resources) after the Students subscription's region policy made the blueprint's `eastus` impossible (founder-approved). Fixed two defects in `main.bicep` (cron jobs were not actually disabled; missing `AZURE_CLIENT_ID` broke user-assigned MI auth). Proved the full async path on Azure with positive attribution, finalized the UTC cron table, created Azure budgets programmatically, verified Heroku ≤ $13. §13.4 admin/static routing **blocked** on the Cloudflare token + Eco subscription. Wrote `PHASE_4_REPORT.md`.
- **Phase 4 (amendment)** — gate reopened to correct a Heroku Eco cost error and finish the two deferred items. Eco is account-wide ($5 / 1,000 h shared), not per-app, so `wtm-admin` was created and deployed on Eco at $0 marginal and staging moved Basic→Eco; total $12/mo. Verified Eco sleep/wake, audited for pingers (none), recorded pool monitoring in `OPS_RUNBOOK.md` §5.1, verified `/r/*` against the Heroku candidate, and added `deploy/site/_headers` for the App Links content type. Cloudflare Pages deploy remains owner-gated on a valid scoped token. Awaiting `APPROVED PHASE 4`.
- **Phase 5** — load/throughput/failure/cost gates measured against staging + the US project with fully synthetic, DO-invisible data (0 residue). All performance, reliability and cron gates PASS; the **cost gate fails at the 30k MAU target** for a structural ACA billing reason (idle-but-billed replicas), corrected for beta/burst by lowering `cooldownPeriod` to 60 s. Wrote `PHASE_5_REPORT.md`. Production and DNS untouched; Azure still not routed. Awaiting `APPROVED PHASE 5`.
- **Phase 4 (deferred item closed)** — Cloudflare Pages candidate deployed + preview-verified on `wtm-site` (preview branch `migration-candidate`) with an Account·Pages-only token; landing, legal, `_headers`, Android asset links and the Apple association file (200 `application/json`, no redirect) all verified. **No production DNS changed**; no custom domain attached. Recorded delta: Pages 308-redirects `.html` to the canonical extensionless URL where Caddy serves it at 200 — update published legal URLs at Phase 6.
