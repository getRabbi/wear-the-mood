# PHASE 4 REPORT — provision Heroku + Azure, deploy candidates (NOT routed)

**Objective:** provision the locked target, deploy non-routed production candidates, and prove the complete async path end-to-end.

**Starting commit:** `17a3a8c` (Phase 3 complete) · **Ending commit:** this commit.
**Result:** ✅ **Target candidates deployed and proven. No production route changed.**

> This phase was **resumed after an interruption**. A recovery audit reconciled the
> cloud/Git/Docker state against the narrative before any change was made; §0 records
> what was already done so nothing was duplicated or re-run.

---

## 0. Recovery audit (resumed session)

The interrupted run stopped between pushing the orchestrator image and pushing the rembg image. Verified-before-acting findings:

| Evidence | State found | Action taken |
|---|---|---|
| Heroku `wtm-api-staging` / `wtm-api-prod` | both existed (container stack, US), staging had 41 config vars, **no dynos, never released** | reused — not recreated |
| GHCR `wtm-api`, `wtm-orchestrator` | pushed 17:21Z / 17:28Z with `17a3a8c` + `migration-candidate` | reused — not rebuilt |
| GHCR `wtm-rembg-worker` | **404 — never pushed**; a local `wtm-rembg-test:latest` existed (built 17:43Z, model baked, module imports) | rebuilt from `rembg-worker.Dockerfile` for provenance, tagged, pushed |
| Azure | providers registered; **0 resource groups, 0 resources, 0 deployments** | deployed fresh |
| Git | `migration/heroku-azure` @ `17a3a8c`, clean, 17 ahead of `origin/main`, unpushed | continued on branch |
| DigitalOcean | api+worker+ofelia+caddy healthy, `/v1/health` 200 | left untouched |

No non-idempotent operation was left in an ambiguous state, so nothing needed a stop-and-ask.

---

## 1. Heroku (§13.1)

| Item | `wtm-api-prod` | `wtm-api-staging` |
|---|---|---|
| Stack / region | container / US common runtime | container / US common runtime |
| Current release | **v4** — `Deployed web (3e99b5dfb3e1)` | v35 |
| Image digest | `sha256:e5d857da…83d002e` | `sha256:e5d857da…83d002e` (**identical artifact**) |
| Config vars | 40 | 40 |
| Dyno | **Basic × 1** (locked spec) | Basic × **0** (see §7 cost) |
| `/healthz` · `/readyz` | 200 · `{"status":"ready","db":true,"environment":"prod","commit":"17a3a8c"}` | 200 · `…"environment":"staging"` |
| Add-ons | none | none |
| Custom domain | `api.wearthemood.com` registered → DNS target `synthetic-castle-h9xyrshjsxcexe5nwsld570w.herokudns.com` | — |

`readyz` returning `db:true` from both apps is the proof that the Heroku plane reaches Supabase **us-east-1** over the Session Pooler on 5432.

**Config reconciliation.** Staging's 41 vars were diffed against the live droplet `.env`. Result: `FCM_CREDENTIALS_JSON` was **missing** (push would have silently failed) and was added to both apps; the six `ENV_MATRIX.md` drift keys (`google_auth_id`, `google_auth_secret`, `OPENAI_MODEL_FALLBACK`, `PHOTOROOM_API_KEY`, `REMOVE_BG_API_KEY`, `BG_REMOVAL_PROVIDER`) were confirmed unread by `config.py` and dropped; `PORT` was deliberately never set (Heroku injects it). `SENTRY_DSN` and `POSTHOG_API_KEY` are empty — **they are empty on the droplet too**, so this is parity, not a regression (owner follow-up).

**Custom domain / certificate.** The domain is registered on the Heroku app, which changes no DNS. `api.wearthemood.com` still resolves to Cloudflare → droplet and still answers 200. ACM cannot validate until the CNAME points at Heroku, so certificate provisioning is a **Phase 6 preflight** step, per the route plan which already schedules this record for Phase 6.

---

## 2. Azure (§13.2)

**Forced deviation — region.** The blueprint locks `eastus`. The Azure for Students subscription enforces a Microsoft-managed policy `Allowed resource deployment regions` = `[koreacentral, austriaeast, uaenorth, malaysiawest, centralindia]`; **no US region is permitted**, and `austriaeast` has no Container Apps support. Deploying to `eastus` fails with `RequestDisallowedByAzure`. **Founder decision: `koreacentral`** — full ACA support and the lowest expected RTT to `us-east-1` of the four viable regions. Recorded in `main.bicep` at the `location` param. Widening the policy requires an Azure support request.

Resource group **`wtm-prod`** / `koreacentral`, 14 resources, deployment `wtm-prod-phase4` = **Succeeded**:

| Resource | Config | Verified |
|---|---|---|
| `wtmprodq4k2n8` | Standard_LRS, TLS1_2, no public blob | ✅ |
| queues `jobs`, `enrichment` | Storage Queue only (no Service Bus) | ✅ both present |
| `wtm-prod-id` (UAMI) | clientId `0f0b54aa-…aba6a` | ✅ |
| RBAC | **Storage Queue Data Contributor**, scoped to the storage account only | ✅ least privilege |
| `wtm-prod-logs` | Log Analytics, 30-day retention (max) | ✅ |
| `wtm-prod-env` | Container Apps **Consumption** | ✅ |
| `wtm-prod-rembg-worker` | 2 vCPU / 4 GiB, **0→3**, azure-queue on `jobs`, queueLength 5 | ✅ exact |
| `wtm-prod-ai-orchestrator` | 0.5 vCPU / 1 GiB, **0→3**, azure-queue on `enrichment` | ✅ exact |
| `wtm-prod-api-emergency` | 0.5 vCPU / 1 GiB, 0→1, `EMERGENCY_API=true` + `EMERGENCY_API_ENABLED=false` | ✅ guarded, no route |
| `wtm-prod-recovery` + 6 cron jobs | see §3 | ✅ all disabled |

No ACR (`Microsoft.ContainerRegistry` deliberately left NotRegistered). All 3 images are pinned by **immutable digest**, not by the floating tag:

```
wtm-api           @sha256:828461c932df07e3dbe595e03d17f585f22e5a4bafb764efe65408f54d7867f0
wtm-rembg-worker  @sha256:6accc51d73b7e317dec3e47cb9a2ae7b73834eb72cf45027b097eae3b5552ea5
wtm-orchestrator  @sha256:34147d22906168692b1febd00b04399479c862fb48174770fdef642b938c2a92
```

12 app secrets are wired as **ACA secret refs** (`supabase-service-role-key`, `connection-string`, …) plus `ghcr-token`; 25 non-secret values are plain env. Private GHCR pull is configured with a `read:packages`-capable token and is **proven working** — the workers pulled and reached `Healthy`.

### Two defects found and fixed this phase

1. **Cron jobs were not actually disabled.** `main.bicep` was commented "created DISABLED" but assigned live schedules. Deploying as-is would have run all six crons against the **live production database while DO's ofelia runs the same six** — duplicate daily pushes, duplicate nightly backups, double credit-reset. ACA Jobs have no `enabled` flag, so `cronSchedulesEnabled` / `recoveryScheduleEnabled` (both default **false**) now select a never-firing expression `0 0 31 2 *`. Verified: all 7 jobs report `0 0 31 2 *`.
2. **Managed identity could not authenticate.** The workers crashed with `ClientAuthenticationError: Unable to load the proper Managed Identity`. A bare `DefaultAzureCredential()` cannot select a **user-assigned** identity; it needs `AZURE_CLIENT_ID`, which the Bicep never set. Added to `baseEnv`. Verified: queue calls now return `200`. This is an infra fix — no application code changed.

---

## 3. Cron schedules (§13.3)

**Timezone evidence (not assumed):** droplet host, `fashionos-ofelia-1`, and `fashionos-api-1` all report `Etc/UTC`, and ofelia has no `TZ` env. So ofelia's calendar shorthands are already UTC.

| Task | Old schedule | Old timezone semantics | New UTC cron | Command |
|---|---|---|---|---|
| news | `@every 6h` | **not clock-aligned** — 6 h after container start, drifts on every restart | `0 */6 * * *` | `python -m app.tasks.news` |
| daily-push | `@hourly` | top of each hour, UTC | `0 * * * *` | `python -m app.tasks.daily` |
| backup | `@daily` | 00:00 UTC | `30 2 * * *` | `python -m app.tasks.backup` |
| spend-alert | `@every 6h` | **not clock-aligned** (as above) | `15 */6 * * *` | `python -m app.tasks.spend_alert` |
| credit-reset | `@daily` | 00:00 UTC | `0 3 * * *` | `python -m app.tasks.credit_reset` |
| giveaway-chats | `@hourly` | top of each hour, UTC | `20 * * * *` | `python -m app.tasks.giveaway_chats` |
| recovery | *(new in Phase 2)* | — | `*/5 * * * *` | `python -m app.tasks.recovery` |

**Proposed deterministic times, with the reasoning recorded as the blueprint requires:** the two `@every 6h` jobs had *no* fixed clock time, so `0 */6` and `15 */6` are proposals, offset 15 min so they never contend. `backup` and `credit-reset` both fired at 00:00 UTC under ofelia; they are separated to 02:30 and 03:00 UTC (low-traffic window, no overlap). `daily-push` must stay hourly because it filters recipients by each user's local `DAILY_PUSH_HOUR`. `giveaway-chats` moves to :20 so the two hourly jobs don't collide.

**All schedules are inert.** Every job carries `0 0 31 2 *` and will keep it until Phase 6 sets `cronSchedulesEnabled=true` after ofelia is retired. Manual `az containerapp job start` is unaffected — that is how `wtm-prod-recovery` was tested (**Succeeded**).

---

## 4. Admin / static routing (§13.4)

> **Correction (gate reopened).** The first version of this section rejected `wtm-admin`
> on a **cost error**: it assumed that, with the Eco subscription unavailable, the admin
> app would need a Basic dyno at +$7/mo. Heroku **Eco is an account-wide $5/month plan
> with 1,000 dyno-hours shared across all personal Eco apps — it is not $5 per app**, so
> a second Eco app costs **$0 marginal**. The owner has since subscribed to Eco, and the
> Gate-0 decision (admin → Heroku Eco `wtm-admin`) is now executed as originally
> specified. The approved allocation is $7 Basic + $5 shared Eco = **$12/month**.

### 4.1 `wtm-admin` — DEPLOYED on Eco ✅

| Item | Value |
|---|---|
| App | `wtm-admin` (personal, **US Common Runtime**, container stack) |
| URL | `https://wtm-admin-aab1ebe5235d.herokuapp.com` |
| Image digest | `sha256:2627d4c41dab7dad13564aad8ceee53f1c705ab47767bd1d197583d01ea209c6` |
| Dyno | **Eco × 1** |
| Config vars | `SUPABASE_SERVICE_ROLE_KEY`, `FASTAPI_BASE_URL`, `ADMIN_PANEL_BASE_PATH`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `NODE_ENV`, `HOSTNAME` (names only) |

**Rebuilt against the US project — this closes a Phase 3 follow-up.** `admin-web` was stopped during the Phase 3 cutover because it was still bound to Tokyo. `NEXT_PUBLIC_*` values are inlined at **build** time, so the image was rebuilt with the US URL/anon key and verified by grepping the built bundle inside the image: the only Supabase host baked in is **`https://ghzabbceoaoertatkjyg.supabase.co`** (US). No Tokyo reference remains.

`FASTAPI_BASE_URL` points at the **Heroku candidate API** (`wtm-api-prod`), not at the live `api.wearthemood.com` — so the candidate chain admin → API is self-contained and no production route is involved.

Smoke + security checks:

| Check | Result |
|---|---|
| `/` (outside basePath) | **404** — basePath obscurity preserved |
| `/mood-ops-console-7x9` | 200 → redirects to `/login` |
| `/mood-ops-console-7x9/dashboard` unauthenticated | **307 → /login** — no data exposure |
| `X-Robots-Tag` | `noindex, nofollow` present |

`ADMIN_IP_ALLOWLIST` is intentionally **unset**, matching the droplet (where it is also empty). The middleware treats empty as "no restriction", and reads the first `X-Forwarded-For` hop, which behaves identically behind Heroku's router as behind Caddy. **Note for the owner:** the console is now reachable at a public `herokuapp.com` hostname rather than only via the apex path, so the boundary is Supabase auth + the obscure basePath. Setting `ADMIN_IP_ALLOWLIST` before Phase 6 is a cheap hardening win.

### 4.2 `/r/*` referral route — VERIFIED against the Heroku candidate ✅

Verified without touching the live route:

| Host | `/r/TESTCODE1` | `/r/abc123` |
|---|---|---|
| Heroku candidate `wtm-api-prod` | **302 → `https://wearthemood.com/`** | 302 → same |
| Live `wearthemood.com` (DO) | **302 → `https://wearthemood.com/`** | — |

Identical behaviour, so the Phase 6 route rule (`/r/*` → Heroku API) is proven to work before any DNS change. The path stays dynamic (it hits the API to record attribution), exactly as the route plan requires.

### 4.3 Cloudflare Pages candidate — ✅ DEPLOYED + VERIFIED (completed post-approval)

> Deployed after the Phase 4 gate, once a correctly-scoped token was supplied. This
> satisfies the binding condition recorded in `MIGRATION_STATE.md`. **No production DNS
> was changed** — the candidate lives only on `*.pages.dev`.

| Item | Value |
|---|---|
| Pages project | `wtm-site` (account `5c06…e82a`) |
| Environment | **preview**, branch `migration-candidate` (not the production branch) |
| Preview URL | `https://migration-candidate.wtm-site.pages.dev` |
| Immutable deploy URL | `https://8939dac3.wtm-site.pages.dev` |
| Custom domains attached | **`wtm-site.pages.dev` only — `wearthemood.com` is NOT attached** |
| Files published | 14 assets + `_headers` parsed as configuration |

**Token scope confirmed minimal.** `/user/tokens/verify` returns `1000 Invalid API Token`
while `/accounts/{id}/pages/projects` succeeds — exactly the signature of an *Account*-scoped
token that cannot reach User or Zone endpoints. It is therefore structurally incapable of
altering production DNS.

**Verification results:**

| Check | Result |
|---|---|
| landing `/` | ✅ 200 `text/html`, 37,129 B |
| `/legal/privacy.html` · `/terms.html` · `/acceptable-use.html` | ✅ 200 after a 308 → canonical extensionless URL (see delta) |
| `/invite/` | ✅ 200 `text/html` |
| `/delete-account.html` | ✅ 200 after 308 |
| **`/.well-known/assetlinks.json`** (Android App Links) | ✅ **200, `application/json`**, valid JSON, no redirect |
| **`/.well-known/apple-app-site-association`** (Universal Links) | ✅ **200, `application/json`**, valid JSON, **no redirect** |
| `_headers` applied | ✅ `/assets/*` → `max-age=86400`; `.well-known` → `max-age=3600` |
| `/assets/site.css`, `/assets/og-image.png` | ✅ 200, `text/css` / `image/png` |
| `/r/*` | ✅ verified in §4.2 against the Heroku candidate (302 → `wearthemood.com/`) |

The `_headers` file did its job: without it Pages would have served the extensionless
`apple-app-site-association` as `application/octet-stream` and silently broken Universal
Links. It is served correctly and **without a redirect**, which the route plan explicitly requires.

**⚠ Behavioural delta to carry into Phase 6.** Cloudflare Pages strips `.html` and issues a
**308** to the canonical extensionless URL; Caddy on the droplet serves `.html` directly at 200.

| URL | Droplet (today) | Pages candidate |
|---|---|---|
| `/legal/privacy.html` | **200** | **308 → `/legal/privacy`** → 200 |
| `/delete-account.html` | **200** | **308 → `/delete-account`** → 200 |

Content is byte-correct at the end of the redirect and browsers/crawlers follow 308s, so the
Play Store listing and in-app links keep working. This is Pages built-in normalisation and
cannot be disabled by configuration. **Action for Phase 6:** update the published Privacy /
Terms / delete-account URLs to the canonical extensionless form so store listings resolve in
one hop instead of two. The `.well-known` files are unaffected — they are served directly.

*Note: bot filtering rejects a default `urllib` User-Agent with 403 on `*.pages.dev`; all
verification above used a normal browser UA. Not a configuration problem.*

### 4.3.1 Original gating record (superseded by the deploy above)

The site payload was inventoried and one **real defect fixed**: `deploy/site/.well-known/apple-app-site-association` has **no file extension**, so Cloudflare Pages would serve it as `application/octet-stream`. Apple requires `application/json` and silently fails Universal Links otherwise. Caddy sets this correctly today, so Pages must reproduce it — added **`deploy/site/_headers`** pinning `application/json` on both App Links files (plus cache policy for `/assets/*` and `/legal/*`). This is committed and ready for the deploy.

Payload to publish (13 files): `index.html`, `delete-account.html`, `invite/index.html`, `legal/{privacy,terms,acceptable-use}.html`, `assets/*` (4), `.well-known/{assetlinks.json,apple-app-site-association}`.

**Deploy is blocked on a valid Cloudflare API token.** `wrangler` 4.112.0 is available, but no credential exists in any environment scope and no OAuth config is present. A token was supplied but was rejected by every auth scheme — `Bearer` → `1000 Invalid API Token`, `/accounts` → `9109`, Pages endpoint → `10000`, Global-API-Key → `9103` — and its `cfk_…` shape does not match Cloudflare's 40-character token format. It was cleared, not stored. **Nothing was faked and no deploy was attempted with an unverified credential.**

Required token scope is deliberately minimal: **Account · Cloudflare Pages · Edit**, with *no* Zone or DNS permission — which makes it structurally incapable of altering production DNS.

**Production is untouched throughout.** `/r/*`, `.well-known`, privacy/terms, the invite page, and the admin console all continue to be served by the droplet exactly as before.

---

## 5. End-to-end candidate test (§13.5)

### 5.1 A first run measured the wrong plane — recorded because it is a real finding

The first attempt inserted a normal `cutout_status='queued'` item. It completed successfully, but three signals were wrong: 1.6 s "cold" pickup, Azure replicas at 0 throughout, and `attempt_count` still 0. Droplet logs confirmed **the DigitalOcean worker did the work**, not Azure.

Root cause is structural, and it matters for Phase 6: DO's `claim_next_item` claims **any** `cutout_status='queued'` row on a 2 s poll, so during the bridge period no wardrobe item in the shared database can avoid it.

> **⚠ Phase 6 hazard (new finding).** DO's `requeue_stale` resets `processing` rows after **120 s**, but the Azure lease (`WORKER_STALE_SECONDS`) is **300 s**. If both planes ever run concurrently, DO will requeue an item that an Azure replica is still legitimately processing. Measured cold rembg time was 47 s, but the very first (model-warmup) run took 104 s — uncomfortably close to 120 s. **The two planes must not overlap on wardrobe cutouts**; the Phase 6 cutover must stop the DO worker before Azure takes cutout traffic.

### 5.2 Isolated re-run — Azure plane proven, attribution confirmed

Isolation: the row is inserted already in `processing` with a 45 s-old lease, and `WORKER_STALE_SECONDS` was temporarily set to 20 on the Azure app (**reverted to 300 afterwards, verified**). DO's claim only sees `'queued'` and its requeue does not fire for 120 s, so only Azure can claim. **Attribution is positively proven**: migration 0044's claim increments `attempt_count`, the pre-Phase-2 code on DO does not — the row came back with `attempt_count=1`.

Full path exercised: `upload → DB row → jobs queue → rembg scale-from-zero → DB claim → cutout → ready → enrichment signal → orchestrator → embedding → final state`.

| Measurement | Result | Phase 5 gate | Status |
|---|---|---|---|
| queue signal delay | 1.5 s (enqueue round trip, laptop→koreacentral) | — | |
| **cold replica start + cold pickup** | **44.3 s** | < 90 s | ✅ inside |
| cold signal → ready | 91.6 s | — | |
| rembg processing | 47.3 s | — | |
| **warm pickup** | **2.9 s** | < 20 s | ✅ well inside |
| warm signal → ready | 6.1 s | — | |
| enrichment (orchestrator, own cold start) | 130.5 s, embedding written ✅ | — | |
| per-job consumption | **94.6 vCPU-s / 189.2 GiB-s** | — | feeds §14.5 |
| duplicate signal ×3 on terminal row | no-op — `attempt_count` 1→1, `cutout_url` stable | zero duplicate output | ✅ |
| garbage + unknown-id messages | both deleted, queue drained to 0 | — | ✅ |
| queue deletion / final depth | `jobs=0`, `enrichment=0` | — | ✅ |
| scale-down to zero | observed, ~600 s cooldown as configured | — | ✅ |
| recovery task | manual execution `wtm-prod-recovery-d39z4w7` → **Succeeded** | — | ✅ |

**Crash recovery (replica kill mid-job) is deliberately deferred to Phase 5 §14.3.** While DO is live, a killed Azure replica leaves a `processing` row that DO's 120 s requeue would grab, so the result would be ambiguous rather than a clean measurement. Phase 5 runs it after the planes are separated.

**Tagging note:** `category`/`tags` came back empty because the Anthropic API returns `400 — credit balance is too low`. This is a **pre-existing account condition**, visible identically in the droplet's own logs, not a migration regression. Embeddings (OpenAI) succeeded, so the enrichment leg itself is proven.

**Data safety (§14.1):** every record belonged to a synthetic user created and deleted per run; images were generated, not real. Post-run verification: **0 residue** across `wardrobe_items`, `profiles`, `auth.users`, with totals back to the Phase 3 baseline exactly (28 items / 27 users).

---

## 6. Webhook candidate tests (§13.6)

Staging endpoint only. **The production webhook URL was not changed.** All events used a synthetic non-existent `app_user_id`, so `apply_webhook_event` returns `False` and nothing is written.

| Test | Result |
|---|---|
| missing `Authorization` | 401 `UNAUTHENTICATED` ✅ |
| invalid signature | 401 `UNAUTHENTICATED` ✅ |
| signature-verified replay | 200 `{ok:true, applied:false}` ✅ |
| idempotent duplicate delivery | byte-identical response, no double-apply ✅ |
| malformed `app_user_id` | 200 `applied=false` — no retry-storm ✅ |
| empty payload | 200 handled ✅ |

**6/6 passed.** FASHN callback replay is **N/A, with evidence**: there is no FASHN callback route in the codebase — try-on is poll-based. Top-up double-credit protection is enforced in SQL (`on conflict (store_txn_id) do nothing`) and is covered by the backend unit suite rather than by mutating live billing data.

---

## 7. Budget alerts and cost (§13.7)

**Azure budgets were created programmatically** — no portal fallback needed. The `az consumption budget create` CLI path is broken (`Invalid budget configuration`), so the REST API was used. Budget `wtm-prod-monthly`, **$100/month**, so the percentage thresholds land exactly on the blueprint's dollar figures:

| Threshold | 10% | 25% | 50% | 75% | 90% | forecast 90% |
|---|---|---|---|---|---|---|
| Alert at | **$10** | **$25** | **$50** | **$75** | **$90** | **$90** |

Azure month-to-date spend: **$0.00**. Six notifications to `uprightseo24@gmail.com`.

**Heroku projected monthly — verified ≤ $13 (corrected):**

Heroku **Eco is a single account-wide $5/month plan providing 1,000 dyno-hours shared across all personal Eco apps** — not $5 per app. Verified live: `heroku ps:type` reports *"$5 (flat monthly fee, shared across all Eco dynos)"* and *"Eco dyno hours quota remaining this month: 1000h 0m (100%)"*.

| Item | Dyno | Cost |
|---|---|---|
| `wtm-api-prod` | Basic × 1 | $7.00 (max) |
| `wtm-api-staging` | **Eco × 1** | — draws on the shared pool |
| `wtm-admin` | **Eco × 1** | — draws on the same shared pool |
| Eco plan (account-wide, both Eco apps) | — | $5.00 |
| Add-ons (none), custom domain + ACM | — | $0.00 |
| **Total** | | **$12.00 / month maximum** ✅ |

$12 ≤ the $13 student-credit ceiling, with $1/month headroom.

**Shared Eco-pool headroom.** 1,000 h/month across two apps. Both sleep after 30 minutes idle, so real consumption is driven by actual use, not wall-clock. The ceiling only binds if both apps ran continuously: 2 × ~730 h = ~1,460 h > 1,000 h. Two Eco apps awake 24/7 would therefore **exhaust the pool around day 20**. This is why §7.1 (no pingers) matters and why the pool is now a tracked runbook metric.

### 7.1 Eco sleep/wake verification

| Check | Result |
|---|---|
| `wtm-api-staging` wakes + healthy | ✅ `/healthz` 200, `/readyz` `db:true, environment:staging` |
| `wtm-admin` wakes + healthy | ✅ 200 at basePath, 307 auth redirect, `noindex` |
| Heroku add-ons (Scheduler would prevent sleep) | ✅ **none** on any of the three apps |
| Scheduled GitHub Actions workflows | ✅ **none** (`migration-build` is push/dispatch, `migration-deploy` is dispatch) |
| `herokuapp.com` referenced in tracked non-doc code | ✅ **none** — the Flutter app still targets `api.wearthemood.com` |
| DO `docker-compose.yml` / `Caddyfile` reference Heroku | ✅ **0 matches** — ofelia crons run Python tasks against the DB, they never call Heroku |
| Azure cron/recovery jobs call Heroku | ✅ no — all inert on `0 0 31 2 *`, and they talk to the DB/queues only |
| Sleep transition observed | ✅ see below |

**No uptime monitor, pinger, or scheduler exists that would keep an Eco dyno awake.** Sleep was observed directly by polling the Heroku **Platform API** (platform API calls generate no web traffic and therefore cannot themselves wake a dyno).

**Observed sleep → wake cycle:**

| App | Sleep | Wake (cold request) | Health after wake |
|---|---|---|---|
| `wtm-api-staging` | `up` → **`idle` at 21:08:55Z**, ~30 min after its last web request — transition sampled at 1-minute resolution | **11.6 s**, HTTP 200 | `/readyz` → `db:true`, `environment:staging` |
| `wtm-admin` | observed **`idle`** | **7.9 s**, HTTP 307 | redirect to `/login` — auth gate still enforced after wake |

*Measurement caveat, stated precisely:* staging's transition was cleanly sampled either side of the 30-minute boundary. For `wtm-admin` the polling host suspended mid-observation (samples jump 21:14Z → 04:42Z), so the dyno was **confirmed idle** but its exact transition moment was not sampled. The conclusion — admin sleeps when idle — is supported independently by the quota evidence below.

**Pool consumption is the strongest evidence that both apps genuinely sleep.** After an overnight period:

```
Eco dyno hours quota remaining this month: 998h 21m (99%)
  wtm-api-staging usage: 1h  5m
  wtm-admin        usage: 0h 32m
```

~1h 37m total consumed. Two dynos held awake across that window would have burned well over 15 h. At this rate the 1,000 h pool is in no danger.

---

## 8. Blocked on the owner

1. ~~**Heroku Eco subscription.**~~ ✅ **RESOLVED** — the owner subscribed to the Eco plan. `wtm-api-staging` and `wtm-admin` both now run **Eco × 1** off the shared 1,000 h pool.
2. **Cloudflare API token** — still blocks the Pages deploy (§4.3). The token supplied was rejected by every auth scheme and was cleared, not stored. Needed scope: **Account · Cloudflare Pages · Edit** only (no Zone/DNS permission, so it cannot alter production DNS). Everything else in §13.4 — `wtm-admin`, the `/r/*` candidate verification, and the `_headers` content-type fix — is complete.
3. **Sentry DSN / PostHog key** are empty on Heroku *and* on the droplet; blueprint §14 wants Sentry live before production traffic.
4. **Anthropic credit balance is empty** — tagging is degraded on the live system today, independent of this migration.
5. Carried from Phase 3: Google OAuth provider config on the US project; final cutover dump encryption; secret rotation.

---

## 9. Tests and scans

- Backend suite: **627 passed, 0 failed** (167 s). Phase 2 reported 625 passed / 2 skipped; the 2 formerly-skipped tests are the Azure-queue ones, which now execute because `azure-storage-queue` + `azure-identity` were installed into the local venv for this phase's tooling. No application code was modified — the only repo change is `infra/azure/main.bicep`.
- Secret scan over tracked non-doc files: **clean** — only `.env.example` placeholders and test fixtures matched.
- No secret value appears in this report, in `main.bicep`, or in any committed file. Deployment parameters containing secrets were written to a scratch file outside the repo, then overwritten and deleted.

---

## 10. Deviations from the blueprint

| # | Blueprint | Actual | Why |
|---|---|---|---|
| 1 | Azure region `eastus` | **`koreacentral`** | Subscription policy forbids all US regions; founder-approved substitute (§2) |
| 2 | staging on Eco | ✅ **staging on Eco × 1** (resolved after the owner subscribed) | — no longer a deviation |
| 3 | cron jobs "created disabled" | disabled via never-firing `0 0 31 2 *` | ACA Jobs have no `enabled` flag |
| 4 | §13.4 admin/static routing | **admin + `/r/*` done**; Pages deploy outstanding | Cloudflare token still missing (§4.3); admin resolved |
| 5 | §13.5 crash recovery | deferred to Phase 5 §14.3 | ambiguous while DO's 120 s requeue is live (§5.1) |

---

## 11. State after Phase 4

**Production is unchanged.** DigitalOcean still serves all traffic; `api.wearthemood.com` still resolves to Cloudflare → droplet and answers 200, and `wearthemood.com/r/TESTCODE1` still returns its usual 302. All four droplet containers are healthy. No DNS record, no webhook destination, and no droplet configuration was modified. The Heroku and Azure planes are deployed, verified, and **idle**: nothing enqueues to the Azure queues (Heroku's `QUEUE_PROVIDER` is unset → `stub`, DO runs pre-Phase-2 code, every schedule is inert), so the workers sit at 0 replicas and both Eco dynos sleep.

Final re-verification after the gate was reopened: Azure **14 resources**, workers **0 replicas**, cron still `0 0 31 2 *`; Heroku `Basic ×1 + Eco ×1 + Eco ×1`; DO `/v1/health` 200.

## 12. Gate reopened — what changed in this amendment

| Item | Before | After |
|---|---|---|
| Eco cost model | wrongly treated as per-app; `wtm-admin` rejected as +$7/mo | **account-wide $5 shared pool**; admin costs $0 marginal |
| `wtm-api-staging` | Basic, scaled to 0 | **Eco × 1**, sleeps and wakes |
| `wtm-admin` | not created | **created, deployed on Eco × 1**, rebuilt against US Supabase, auth-gated |
| Heroku total | $7.00/mo (staging parked) | **$12.00/mo** — the approved allocation |
| `/r/*` on Heroku candidate | untested | **verified 302, identical to live** |
| Pages `.well-known` content type | latent defect | **`_headers` added** pinning `application/json` |
| Eco sleep/wake + pinger audit | n/a | **verified** — sleeps, wakes in 8–12 s, no pingers, 99% quota left |
| Cloudflare Pages deploy | owner-gated | still owner-gated (invalid token supplied, cleared) |

## Next approval phrase

```
APPROVED PHASE 4
```
