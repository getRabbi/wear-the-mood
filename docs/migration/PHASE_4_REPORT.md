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

## 4. Admin / static routing (§13.4) — BLOCKED, not skipped

The Gate-0 subplan (admin → Heroku Eco `wtm-admin`; landing/legal/`.well-known` → Cloudflare Pages; `/r/*` preserved to the API) could **not** be executed:

- **Cloudflare Pages** needs a Cloudflare API token. `infra/cloudflare/route-plan.md` already records the full export as "gated on the Cloudflare API token", and none is available to this environment.
- **`wtm-admin` on Heroku Eco** is blocked by the same Eco subscription blocker as staging (§7). Creating it on Basic instead would add $7/mo and push the Heroku total to $21/mo — well over the locked $13 ceiling — so it was deliberately **not** created.

Nothing was faked and no route was flipped. `/r/*`, `.well-known`, privacy/terms, and the admin console all continue to be served by the droplet exactly as before. Both items are owner-gated and carried into Phase 6 preflight.

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

**Heroku projected monthly — verified ≤ $13:**

| Item | Cost |
|---|---|
| `wtm-api-prod` — 1 Basic web dyno | $7.00 |
| `wtm-api-staging` — scaled to **0 dynos** after testing | $0.00 |
| Add-ons (none), custom domain + ACM | $0.00 |
| **Total** | **$7.00 / month** ✅ |

Staging was found running on **Basic** rather than the specified Eco (see §8) — leaving it up would have cost $14/mo and **breached the $13 ceiling**, so it was scaled to zero. Once Eco is subscribed the intended steady state is $7 + $5 = **$12/mo**, still inside the ceiling. Phase 5 re-scales staging for load testing.

---

## 8. Blocked on the owner

1. **Heroku Eco subscription.** `heroku ps:type web=eco` fails with *"The app owner has to subscribe to Eco"*. This is an account-level subscription with **no CLI or API endpoint** (`/account/eco-dyno-hours` → 404), so it needs a browser: <https://dashboard.heroku.com/account/billing> → subscribe to Eco, then `heroku ps:type web=eco -a wtm-api-staging`. Blocks the Eco half of the cost model and the `wtm-admin` app.
2. **Cloudflare API token** — blocks the Pages project and the §13.4 route work.
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
| 2 | staging on Eco | staging on Basic, **scaled to 0** | Eco subscription is browser-only (§8.1); scaling to 0 keeps the cost gate met |
| 3 | cron jobs "created disabled" | disabled via never-firing `0 0 31 2 *` | ACA Jobs have no `enabled` flag |
| 4 | §13.4 admin/static routing | **not executed** | Cloudflare token + Eco both owner-gated (§4) |
| 5 | §13.5 crash recovery | deferred to Phase 5 §14.3 | ambiguous while DO's 120 s requeue is live (§5.1) |

---

## 11. State after Phase 4

**Production is unchanged.** DigitalOcean still serves all traffic; `api.wearthemood.com` still resolves to Cloudflare → droplet and answers 200. No DNS record, no webhook destination, and no droplet configuration was modified. The Heroku and Azure planes are deployed, verified, and **idle**: nothing enqueues to the Azure queues (Heroku's `QUEUE_PROVIDER` is unset → `stub`, DO runs pre-Phase-2 code, every schedule is inert), so the workers sit at 0 replicas.

## Next approval phrase

```
APPROVED PHASE 4
```
