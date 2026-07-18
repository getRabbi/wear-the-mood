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
| Current phase | **Phase 4 complete — HARD STOP at Gate 4** (target candidates deployed, NOT routed) |
| Last completed | Phase 4 — Heroku + Azure provisioned, async path proven end-to-end |
| DigitalOcean role | **LIVE PRODUCTION on the US DB** (api+worker+ofelia repointed to `us-east-1`) — bridge until Phase 6 compute cutover + 48h soak. **Untouched by Phase 4.** |
| Authoritative DB | **Supabase US `ghzabbceoaoertatkjyg` (us-east-1)** — Tokyo retained as cold backup (do NOT delete) |
| Next human approval phrase | `APPROVED PHASE 4` |

---

## Phase gate tracker

| Phase | Description | Status | Gate phrase |
|---|---|---|---|
| Bootstrap | Branch + state files | ✅ complete | — |
| 0 | Read-only discovery | ✅ approved | `APPROVED PHASE 0` |
| 1 | Encrypted backup + restore proof | ✅ approved | `APPROVED PHASE 1` |
| 2 | Code refactor + reproducible IaC (DO unchanged) | ✅ approved | `APPROVED PHASE 2` |
| 3 | Supabase Tokyo → us-east-1 migration | ✅ approved | `APPROVED PHASE 3` |
| 4 | Provision Heroku + Azure, deploy candidates (not routed) | ✅ complete — awaiting gate (deployed + proven, not routed) | `APPROVED PHASE 4` |
| 5 | Load / throughput / failure / cost gates | ⛔ not started | `APPROVED PHASE 5` |
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

## Deployed target inventory (Phase 4 — candidates, NOT routed)

No secret values. Names, digests, and identifiers only.

| Item | Value |
|---|---|
| Heroku prod app / release | `wtm-api-prod` / **v4**, Basic ×1, container stack, US |
| Heroku staging app / release | `wtm-api-staging` / v35, **scaled to 0** after testing |
| Heroku API image digest (both) | `sha256:e5d857da6fdcfa1232cbdb405b5a2583b5288de203ddb302c5497999583d002e` |
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
- **Cost:** Azure budget `wtm-prod-monthly` created **programmatically** ($100 base → alerts at exactly $10/$25/$50/$75/$90 + forecast). Azure MTD **$0**. Heroku **$7.00/mo** ≤ $13 gate (staging at 0 dynos).
- **Blocked on owner:** Heroku **Eco subscription** (browser-only, no API) — blocks staging-on-Eco and `wtm-admin`; **Cloudflare API token** — blocks §13.4 Pages/route work. Neither was faked; no route was flipped.
- Tests **627 passed**; secret scan clean; only repo change is `infra/azure/main.bicep`.

## Change log

- **Bootstrap** — created `migration/heroku-azure` from `origin/main@98df3c3`; created this file; verified current-phase prerequisites.
- **Phase 0** — read-only discovery complete; wrote `DISCOVERY.md`, `ENV_MATRIX.md`, `PHASE_0_REPORT.md`; no infra changes. **APPROVED PHASE 0** with binding clarifications (media backup = Supabase Storage; admin → Heroku Eco `wtm-admin`; static → CF Pages + `/r/*`→Heroku; runtime DSN = Session Pooler 5432; R2 = encrypted backups only).
- **Phase 1** — encrypted backup + restore proof complete; wrote `BACKUP_MANIFEST.md`, `ROLLBACK_RUNBOOK.md`, `PHASE_1_REPORT.md`. DO snapshot taken; encrypted archive uploaded to R2 + restore-verified. **APPROVED PHASE 1**.
- **Phase 2** — code refactor + reproducible IaC complete (11 commits, DO unchanged); wrote `PHASE_2_REPORT.md`. 625 tests pass; migration 0044 created (not applied to prod). **APPROVED PHASE 2** (media→Storage; admin→Heroku Eco; static→CF Pages; DSN=Session Pooler 5432; R2=backups only).
- **Phase 3** — Tokyo → us-east-1 cutover COMPLETE + verified (US `ghzabbceoaoertatkjyg`). DB restored (all counts match, 0044 applied, FK ok), 120/120 Storage objects migrated, 143 URL rows rewritten, DO bridge repointed to US (Session Pooler 5432), smoke PASS. Tokyo retained cold. **Rollback boundary crossed.** Wrote `PHASE_3_REPORT.md` + `HUMAN_HANDOFF.md`. Pending: owner encrypts final dump; auth-provider config on US; admin-web rebuild. **APPROVED PHASE 3**.
- **Phase 4** — resumed after interruption (recovery audit first, nothing duplicated). Pushed the missing `wtm-rembg-worker` image; released the same immutable API artifact to Heroku staging + prod (prod v4, Basic ×1, `db:true`); registered `api.wearthemood.com` without touching DNS; deployed Azure `wtm-prod` in **`koreacentral`** (14 resources) after the Students subscription's region policy made the blueprint's `eastus` impossible (founder-approved). Fixed two defects in `main.bicep` (cron jobs were not actually disabled; missing `AZURE_CLIENT_ID` broke user-assigned MI auth). Proved the full async path on Azure with positive attribution, finalized the UTC cron table, created Azure budgets programmatically, verified Heroku ≤ $13. §13.4 admin/static routing **blocked** on the Cloudflare token + Eco subscription. Wrote `PHASE_4_REPORT.md`. Awaiting `APPROVED PHASE 4`.
