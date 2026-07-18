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
| Current phase | **Phase 3 in progress** — rehearsal PASS; awaiting the US project + `AUTHORIZE SUPABASE CUTOVER` |
| Last completed | Phase 2 — code refactor + reproducible IaC (approved) |
| DigitalOcean role | **LIVE PRODUCTION** (remains the bridge until Phase 6 cutover passes a 48h soak) |
| Next human action | create the `us-east-1` project + mirror config, then reply `AUTHORIZE SUPABASE CUTOVER` |

---

## Phase gate tracker

| Phase | Description | Status | Gate phrase |
|---|---|---|---|
| Bootstrap | Branch + state files | ✅ complete | — |
| 0 | Read-only discovery | ✅ approved | `APPROVED PHASE 0` |
| 1 | Encrypted backup + restore proof | ✅ approved | `APPROVED PHASE 1` |
| 2 | Code refactor + reproducible IaC (DO unchanged) | ✅ approved | `APPROVED PHASE 2` |
| 3 | Supabase Tokyo → us-east-1 migration | 🔄 prep done (rehearsal PASS); awaiting US project + `AUTHORIZE SUPABASE CUTOVER` | `APPROVED PHASE 3` |
| 4 | Provision Heroku + Azure, deploy candidates (not routed) | ⛔ not started | `APPROVED PHASE 4` |
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

## Change log

- **Bootstrap** — created `migration/heroku-azure` from `origin/main@98df3c3`; created this file; verified current-phase prerequisites.
- **Phase 0** — read-only discovery complete; wrote `DISCOVERY.md`, `ENV_MATRIX.md`, `PHASE_0_REPORT.md`; no infra changes. **APPROVED PHASE 0** with binding clarifications (media backup = Supabase Storage; admin → Heroku Eco `wtm-admin`; static → CF Pages + `/r/*`→Heroku; runtime DSN = Session Pooler 5432; R2 = encrypted backups only).
- **Phase 1** — encrypted backup + restore proof complete; wrote `BACKUP_MANIFEST.md`, `ROLLBACK_RUNBOOK.md`, `PHASE_1_REPORT.md`. DO snapshot taken; encrypted archive uploaded to R2 + restore-verified. **APPROVED PHASE 1**.
- **Phase 2** — code refactor + reproducible IaC complete (11 commits, DO unchanged); wrote `PHASE_2_REPORT.md`. 625 tests pass; migration 0044 created (not applied to prod). Awaiting `APPROVED PHASE 2`.
