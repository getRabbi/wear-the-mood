# OPS_RUNBOOK.md — Fashion OS operations (Phase 4 deliverable)

Practical runbook for the live stack: **DigitalOcean droplet** (`docker compose`:
api + worker + ofelia + caddy), **Supabase** (Postgres 17, managed), **Cloudflare
R2** (public `fashionos-public` via `cdn.wearthemood.com` + private
`fashionos-private`). Deploy is **manual** (no auto-deploy, no git on the droplet).

---

## 1. Deploy / redeploy the backend

The droplet at `/root/fashionos` is a **file copy, not a git checkout**. To ship new
backend code:

```bash
# from the dev machine (backend/ as cwd), sync code (excludes .env/.venv/caches):
tar czf - --exclude='.env*' --exclude='.venv' --exclude='__pycache__' \
    --exclude='*.pyc' --exclude='.pytest_cache' app scripts requirements*.txt pyproject.toml \
  | ssh root@<DROPLET_IP> 'cd /root/fashionos/backend && tar xzf -'
# also sync docker-compose.yml / backend/Dockerfile if they changed.
ssh root@<DROPLET_IP> 'cd /root/fashionos && docker compose up -d --build'
```

Secrets live in `/root/fashionos/backend/.env` (git-ignored). Always back it up
before editing: `cp .env .env.bak.$(date +%Y%m%d-%H%M%S)`.

**Verify after deploy:** `curl -s -o /dev/null -w "%{http_code}\n" https://api.wearthemood.com/v1/health` → 200.

## 2. Roll back a release

No git on the droplet, so rollback = redeploy the previous code:
```bash
git checkout <previous-good-sha>          # on the dev machine
# re-run the tar-sync + `docker compose up -d --build` from §1.
git checkout main                          # restore your working tree afterwards
```
A failed `--build` keeps the **old containers running** (Compose builds before
recreating), so a broken build does not take prod down. Roll back `.env` changes
with the `.env.bak.*` copy.

## 3. Database backup & restore

- **Automatic:** ofelia runs `python -m app.cron.backup` **`@daily`** →
  `pg_dump` (custom format) to private R2 at `backups/<env>/<UTC-timestamp>.dump`,
  keeping the most recent `BACKUP_KEEP` (default 7).
- **Requires** `CONNECTION_STRING_DIRECT` (direct **5432**) in `backend/.env` —
  pg_dump cannot run through the 6543 transaction pooler. Without it the cron
  **skips** (logs the reason).
- **Manual backup now:** `ssh root@<IP> 'cd /root/fashionos && docker compose exec api python -m app.cron.backup'`
- **Restore** (to a scratch/replacement DB — never blind-restore over prod):
  1. Download the dump from R2 (`backups/<env>/<ts>.dump`) — Cloudflare dashboard
     or `aws s3 cp --endpoint-url <R2_ENDPOINT> s3://fashionos-private/backups/...`.
  2. `pg_restore --no-owner --no-privileges --clean --if-exists -d "<CONNECTION_STRING_DIRECT>" <file>.dump`
  3. Verify row counts / a few tables before pointing traffic at it.
- Supabase Pro daily backups / PITR are the primary; the R2 dump is the
  independent off-platform copy.

## 4. Kill switches

| Switch | Effect | How |
|---|---|---|
| **AI try-on** (`ai_tryon_enabled`) | `POST /v1/tryon` → 503 + friendly msg; **halts FASHN spend**; free 2D unaffected | `insert into feature_flags(key,enabled) values('ai_tryon_enabled',false) on conflict (key) do update set enabled=false;` — restore: set `true` or delete the row |
| **Storage write-gate** (`STORAGE_WRITES`) | `legacy` = new uploads to Supabase; `r2` = new uploads to R2 (reads resolve per-record either way) | edit `backend/.env`, `docker compose up -d` |

Run flag SQL in the Supabase SQL editor (or `apply_sql.py`). Effect is immediate —
no redeploy.

## 5. Cost monitoring

**Projected infrastructure cost after the migration** (verified Phase 5, §E):

| Component | At launch | At 30k MAU |
|---|---|---|
| Heroku (Basic ×1 + account-wide Eco) | $12.00 | $12.00 |
| Azure Container Apps Jobs (per-execution) | **$0.00** | $7.73 |
| Azure Storage Queue + Log Analytics | ~$0.01 | ~$0.01 |
| Supabase | $0 (free tier) | upgrade to Pro when limits bite |
| **Total** | **~$12/month** | **~$19.73/month** |

Azure budget `wtm-prod-monthly` alerts at $10/$25/$50/$75/$90 (+forecast $90). The
$16.67/month Azure ceiling holds at 30k MAU with ~2× headroom. Recheck the projection if
the worker sizing, batch size, or `cooldownPeriod` changes — see §5.2.

- ofelia runs `python -m app.cron.spend_alert` **`@every 6h`**: sums the last 24h
  of `ai_usage_log.estimated_usd`; when `>= DAILY_COST_ALERT_USD` (default 25, `0`
  disables) it logs ERROR + a **Sentry** event. On alert → flip the try-on
  kill-switch (§4), investigate `ai_usage_log`.
- Manual check: `docker compose exec api python -m app.cron.spend_alert`.

### 5.1 Heroku shared Eco dyno-hour pool (migration candidates)

Heroku **Eco is one account-wide $5/month plan giving 1,000 dyno-hours shared across
every personal Eco app** — it is *not* $5 per app. Two Eco apps currently draw on the
same pool:

| App | Dyno | Notes |
|---|---|---|
| `wtm-api-prod` | Basic × 1 | $7/mo, **not** in the Eco pool, never sleeps |
| `wtm-api-staging` | Eco × 1 | sleeps after 30 min idle |
| `wtm-admin` | Eco × 1 | sleeps after 30 min idle |

Approved ceiling: **$7 Basic + $5 Eco = $12/month** (limit $13).

**Why this needs watching.** 1,000 h/month is comfortable only because Eco dynos sleep.
If both apps stayed awake continuously they would need ~1,460 h and **exhaust the pool
around day 20**, after which Eco apps stop serving until the quota resets. So:

- **Never** add an uptime monitor, pinger, health-check cron, or Heroku Scheduler add-on
  against `wtm-api-staging` or `wtm-admin`. That is the single biggest pool risk.
- Audited clean at Phase 4: no add-ons on any app, no scheduled GitHub Actions workflow,
  no `herokuapp.com` reference in tracked non-doc code, and no reference from the droplet's
  `docker-compose.yml` / `Caddyfile`.
- Prefer keeping load/soak testing (Phase 5) time-boxed — a 30-minute k6 run against
  staging costs ~0.5 h of pool, but leaving staging awake all day costs ~24 h.

**Monthly check** (safe: the Platform API generates no web traffic, so it cannot wake a
sleeping dyno):

```bash
heroku ps -a wtm-api-staging   # prints "Eco dyno hours quota remaining this month"
heroku ps -a wtm-admin         # per-app usage share
heroku ps:type -a wtm-api-staging   # confirms the $5 flat shared fee
```

Act if remaining quota drops below ~40% before the 20th of the month: find what is keeping
a dyno awake (`heroku logs -a <app> --source heroku --dyno router`), or scale the idle app
to `web=0` until needed.

### 5.2 Azure worker plane — event-driven Jobs (migration target)

Background removal and enrichment run as **event-driven Container Apps JOBS**, not
always-on Container Apps. This is a cost-critical distinction: ACA bills allocated
resources for as long as a replica lives, so the previous always-on design projected
**~$150/month** at 30k MAU; Jobs bill per execution and the same load measures
**$7.73/month**.

| Resource | Trigger | Size | Limits |
|---|---|---|---|
| `wtm-rembg-job` | `jobs` queue | 2 vCPU / 4 GiB | min 0, **max 3**, poll 5s, timeout 600s, retry 1 |
| `wtm-ai-orchestrator-job` | `enrichment` queue | 0.5 vCPU / 1 GiB | same |

**Never reintroduce an always-on worker Container App.** A persistent warm replica
recreates the ~$150/month structural cost and breaks the $16.67/month ceiling.

**Batch size is the cost lever.** Every execution pays ~43s of interpreter + ONNX
model load, amortised across the batch:

| batch | 30k MAU |
|---|---|
| 10 | $23.76/mo (over ceiling) |
| 50 | **$7.73/mo (current)** |

Tune via `REMBG_BATCH_MAX_JOBS` / `ORCHESTRATOR_BATCH_MAX_JOBS` / `BATCH_MAX_SECONDS`.
Keep `BATCH_MAX_SECONDS` below the job `replicaTimeout` (600s) so a batch exits on
its own terms instead of being killed mid-write.

**Expected latency is NOT interactive.** Jobs have no warm pool, so activation p95 is
~100s (image pull ~50s + model load ~43s + poll ≤5s) and end-to-end p95 ~110s. That is
by design for asynchronous background work. The client shows a reassuring
"still preparing" state after 45s and must never present this as a failure.

Checks:
```bash
az containerapp job execution list -g wtm-prod -n wtm-rembg-job -o table
# batch summaries (processed / startup_s / avg_job / reason) land in Log Analytics:
#   ContainerAppConsoleLogs_CL | where Log_s has 'batch done'
```
An execution that errors on every poll and processes nothing exits **non-zero**, so a
broken environment shows as `Failed` rather than a misleading `Succeeded`.

**Deferred (post-cutover, not a launch blocker):** the ~100 s activation is dominated by
ONNX session init (~43 s) and image pull (~50 s), so the only meaningful lever left is a
smaller/faster model (ISNet / quantized U2Net). Evaluate that on **real devices with real
garments** — it is a cutout-quality decision, not something to tune against synthetic
load. Do not swap the model without re-checking `LICENSES.md` (§2.2: MIT/Apache only).

### 5.3 API capacity envelope (measured, Phase 5 §E)

Measured on `wtm-api-staging` (Eco, same 1× dyno class as prod Basic) from a US-region
generator co-located with the dyno — GitHub Actions workflow `loadtest`, dispatch-only.

| Metric | Measured |
|---|---|
| Sustained rate | **120 RPS for 30 min** (216,000 requests, 0 dropped) |
| Errors | **0.00 %** (0 of 216,000) |
| read p95 / p99 | **47.3 ms / 54.3 ms** |
| write p95 / p99 | **42.5 ms / 48.2 ms** |
| Peak dyno memory | 80 MB of 512 MB · zero R14/R15 |
| DB connections | 24/60 (40 %), flat |

One Basic dyno covers the launch envelope with large headroom; scale by adding dynos
before touching anything else. **Measure from a US-region source.** A generator in
Bangladesh bakes ~250–280 ms of RTT into every sample and caps out around 106 RPS — that
is the harness, not the dyno, and reading it as a capacity finding is a mistake this
project has already made once.

### 5.4 Running the load test safely — data hygiene

`.github/workflows/loadtest.yml` is **manual dispatch only** and must never fire on push.
Two standing hazards:

1. **It writes to the authoritative production database.** Staging shares the prod
   Supabase project, and the k6 mix includes `POST /v1/outfits` (~2 % of iterations), so a
   30-minute run at 120 RPS creates **~4,300 outfit rows** plus its synthetic users and
   items. The run does **not** clean up after itself — tear down explicitly afterwards.
2. **Never let it create `tryon_jobs` or `ai_jobs`.** The live DO worker would claim them
   and call the **paid** FASHN / image-gen providers. Seed every synthetic wardrobe item
   with `cutout_status='done'` so it is structurally unclaimable (the worker only claims
   `'queued'` and only requeues `'processing'`).

Teardown is fenced to `@wtm-migration-test.invalid` with known synthetic prefixes, and
aborts unless totals return to the baseline (**27 `auth.users` / 28 `wardrobe_items`**).
Verify after any run:

```sql
select count(*) from auth.users where email like '%@wtm-migration-test.invalid';  -- 0
select count(*) from public.outfits where name like 'wtm-p5%';                    -- 0
select count(*) from public.wardrobe_items where title like 'wtm-p5%';            -- 0
```

Also assert that **no marker-named row is owned by a real user** — that check is what
proves a load run never mutated production data.

## 6. Deletion & retention timeline

| Data | When | Retention |
|---|---|---|
| **Account deletion** (`DELETE /v1/account`) | user request | **Immediate** erasure: all images in **both R2 buckets + every Supabase bucket** (prefix `<uid>/`) + `media_assets` rows + DB cascade. No retention (GDPR). |
| **Content deletion** (wardrobe / post / giveaway / try-on photo) | user request | **Immediate**: the item's object(s) deleted (public URL stops resolving at once) + `media_assets` row soft-deleted (`deleted_at`). |
| **Try-on input images** | after processing | Provider-side (FASHN) ~72h; we don't persist raw inputs long-term (§10). |
| **Migrated legacy Supabase objects** (Phase 1) | n/a | **Retained** (old app still reads them); sweep only after the new app is fully rolled out. |
| **DB backups** in R2 | nightly | Last `BACKUP_KEEP` (7) dumps; older auto-pruned. |

All deletion is **best-effort + logged + idempotent** — a storage hiccup never
blocks the DB delete; any orphan is caught by the next account-level prefix sweep.

## 7. Health & logs

- Health: `GET /v1/health` (via Caddy). Services: `docker compose ps` (api,
  worker, ofelia, caddy — all `restart: unless-stopped`).
- Logs: `docker compose logs --tail=100 <api|worker|ofelia>`. Errors → **Sentry**.
