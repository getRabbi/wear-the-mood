# PHASE 0 REPORT — Read-only discovery

**Objective:** produce a verified map of the current Wear The Mood system and surface blockers before any backup or refactor. Read-only; DigitalOcean untouched as live production.

**Starting commit:** `98df3c359ff711d4949e27b7ac2de4528602829b` (`origin/main`, migration branch base)
**Bootstrap commit:** `9af0588` (migration state tracker)
**Ending commit:** this commit (adds `DISCOVERY.md`, `ENV_MATRIX.md`, `PHASE_0_REPORT.md`; updates `MIGRATION_STATE.md`).

---

## What was verified

- **Repo/infra facts corrected** against reality (see `DISCOVERY.md §1`). Deploy path `/root/fashionos` ✅, Tokyo `ap-northeast-1` ✅, PG **17.6**, hostnames Cloudflare-proxied ✅.
- **Compute:** one droplet (Ubuntu 24.04, 2 vCPU, 3.8 GiB), compose project `fashionos`, 5 services (`api`, `worker`, `admin-web`, `caddy`, `ofelia`), file-sync deploy, ufw 22/80/443.
- **Job model:** combined DB-polling worker; all claims already use `FOR UPDATE SKIP LOCKED`; **no Redis/broker** (Postgres is the source of truth). Stale-recovery exists only for `wardrobe_items` cutout.
- **Money paths idempotent:** `spend_credit`/`refund_credit`/`grant_credits` idempotent on `ref` under row locks → no double-charge/refund.
- **Six crons** confirmed (exact commands/schedules in `DISCOVERY.md §4`); a 7th (`community.py`) exists unscheduled.
- **DB:** 19 MB, 59 tables (RLS 59/59), 67 policies, 197 funcs, 20 triggers, 7 seqs; extensions all standard (`vector 0.8.0`, `pgcrypto`, `uuid-ossp`, `supabase_vault`, `pg_stat_statements`); Realtime publication has **0 tables** (app polls).
- **Auth:** 27 users (google 16, email 11) — 11 password hashes to migrate.
- **Media:** **Supabase Storage**, 5 buckets, **120 objects / ~72 MB** (`STORAGE_WRITES=legacy`). R2 holds nightly DB dumps only.
- **Split-brain:** app uses Supabase **Auth + Storage only**; **no direct DB access** (no `.rpc`/`.from('table')`); no force-update gate → LOW risk, reversible freeze proposed.
- **Integrations:** FASHN (poll), RevenueCat webhook `POST /v1/billing/webhook`, FCM live, OpenAI/Anthropic, Sentry/PostHog, R2. No runtime dependency on the raw droplet IP.

## Commands run (representative; secrets redacted)

- Git: `git switch -c migration/heroku-azure origin/main`; local exclude of the blueprint.
- SSH (read-only): `hostnamectl`, `docker ps/image ls/volume ls`, `docker compose ls/ps`, `ufw status`, env **key-name** extraction via `sed -n 's/^…\(NAME\)=.*/\1/p'` (values never printed), provider-mode + port/region greps (no DSN printed).
- Live Supabase (read-only SELECTs, run inside the droplet's `worker` container so the DSN never left the container): `pg_database_size`, `pg_extension`, `pg_stat_user_tables`, critical `count(*)`, `pg_policies`, `storage.buckets`/`storage.objects`, `pg_publication_tables`, `auth.identities` provider counts.
- Tests: isolated venv in scratchpad → `pytest -q`. DNS: `Resolve-DnsName` for the 4 hostnames. CI: `gh api …/check-runs`, `gh run view --log-failed`.

## Tests & results

- **Backend: `580 passed, 2 skipped`** (`pytest -q`, isolated venv, ~137 s). Green.
- **Flutter:** ~579 tests static (117 files); not executed (needs `build_runner`) — Phase 2 CI.
- **CI on `main`: RED = formatting only** (`ruff format --check`, `dart format --set-exit-if-changed`) — fails before test steps; **not** a test/runtime failure. Pre-existing; out of Phase 0 scope. Founder hygiene item.

## Cost-impact check

**Zero.** Phase 0 created no cloud resources (no Heroku app, no Azure resource, no Supabase project, no snapshot/backup, no DNS change). Only local repo docs + a read-only sweep.

## Discovered deviations (detail in `DISCOVERY.md §1, §9`)

1. **(Major) Media on Supabase Storage, not R2** → Phase 3 must migrate ~72 MB/120 objects Tokyo→US and rewrite legacy absolute public URLs.
2. **Admin on droplet** (believed off) → target Heroku Eco `wtm-admin`.
3. **Static site + `/r/*` on droplet Caddy** → Cloudflare Pages + Heroku-API route.
4. **No stale-recovery for `tryon_jobs`/`ai_jobs`; output tables lack job-id uniqueness** → Phase 2 reliability fields + recovery + uniqueness.
5. **Runtime DSN 6543** → move to Session Pooler 5432 (per confirmed decision; no requirement forces 6543).
6. Minor: unscheduled `community.py` cron; extra unused droplet env keys; `LLM_PRIMARY=openai`; CI format drift.

## Unresolved risks

- Supabase Storage object migration + public-URL rewrite correctness (mitigate: rehearse in Phase 3; small volume).
- Reprocessing safety must land before enabling queue recovery (Phase 2).
- Live Cloudflare/R2 config export + Supabase dashboard auth mirror still pending the CF token / dashboard (human) — scheduled for Phase 1 / Phase 3, not Phase 0 blockers.

## Rollback state

Nothing to roll back. DigitalOcean is fully intact and serving production unchanged. Work exists only on branch `migration/heroku-azure` (docs only). The blueprint input file remains untouched and uncommitted.

## Secret scan

Pattern scan of the committed migration docs + working tree for high-signal secret patterns (JWT `eyJ…`, `sk-…`, `postgres://…:…@`, `service_role`, R2/AWS keys, private keys): **clean** — names-only, no values.

## Next approval phrase

```
APPROVED PHASE 0
```
