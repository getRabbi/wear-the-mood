# PHASE 6 REPORT — production cutover and 48-hour soak

> **STATUS: IN PROGRESS — soak running.** The cutover is complete and verified.
> The 48-hour soak began **2026-07-20 12:35Z** and ends **~2026-07-22 12:35Z**.
> This report is finalized only when the full soak has elapsed. It is **not** a pass
> record yet.

---

## 1. Final live infrastructure

| Layer | Live target | Evidence |
|---|---|---|
| **API** | Heroku `wtm-api-prod` (Basic ×1, release v5, commit `0851595`) | `api.wearthemood.com` → `via: 2.0 heroku-router`; `/healthz` `/readyz` `/v1/health` all 200, `db:true` |
| **Website** | Cloudflare Pages `wtm-site` (prod branch `main`) | `wearthemood.com` → `CNAME wtm-site.pages.dev`, proxied |
| **Workers** | Azure Container Apps **Jobs** (event-driven, never always-on) | `wtm-rembg-job`, `wtm-ai-orchestrator-job` |
| **Scheduled jobs** | Azure — `wtm-prod-recovery` `*/5`, six `wtm-prod-cron-*` | 56 recovery + 10 cron executions in the first 4h41m, **0 failures** |
| **Database** | **Supabase US `ghzabbceoaoertatkjyg` (us-east-1)** — authoritative | 14/60 connections (23%) |
| **Rollback** | DigitalOcean droplet `159.65.248.247` — `api`+`caddy` running | Untouched; `worker`+`ofelia` intentionally stopped |

Images (CI-built, `a6d0cde`): `wtm-rembg-worker@sha256:12016768…`, `wtm-orchestrator@sha256:44680cb2…`.

## 2. Cutover record

| Event | Time (UTC) |
|---|---|
| DO `worker`+`ofelia` stopped | 2026-07-20 12:06:01 (attempt 1) / 12:28:18 (attempt 2) |
| Azure recovery + six crons enabled | 12:28:18 |
| **API DNS flipped** (`A 159.65.248.247` → `CNAME …herokudns.com`) | 12:28:19 |
| `heroku certs:auto:refresh` | 12:30:33 |
| ACM certificate issued | ~12:31 |
| **API HTTPS live on Heroku** | 12:32:07 |
| Cloudflare proxy re-enabled on `api` | 12:35:12 |
| **48-hour soak started** | **12:35** |
| Pages production deploy (`b8a9be7b`) | ~12:58 |
| `wearthemood.com` attached to `wtm-site` | ~13:01 |
| **Website apex flipped** to Pages | 13:02:51 |
| `404.html` deployed (`bb37cfda`) | ~13:2x |

**First attempt failed and was rolled back** (~12 min API outage, 12:09:52→12:21:59): Heroku ACM
never issued because it sat in a `Failed` state and does not retry on its own. The fix —
forcing `certs:auto:refresh` immediately after the flip — cut the second attempt's window to
**3 min 48 s**. Full detail in `MIGRATION_STATE.md`.

## 3. Cutover verification (all passed)

**API** — `/healthz`, `/readyz` (`db:true`, `environment:prod`), `/v1/health` 200 both DNS-only
and proxied · origin confirmed `via: 2.0 heroku-router` · TLS `CN=api.wearthemood.com`,
Let's Encrypt, valid to **2026-10-18**.

**Website** — landing 200 · `/legal/privacy`, `/legal/terms`, `/legal/acceptable-use` 200
(extensionless, per owner decision) · `/delete-account` 200 · `/invite/` 200 · `.html` forms
308 → canonical extensionless · unknown paths **404** (real 404 page, not a soft 404) ·
HTTPS `CN=wearthemood.com`, valid to 2026-09-19.

**Deep links** — `.well-known/assetlinks.json` and `.well-known/apple-app-site-association`
both **200 `application/json`, 0 redirects** (Android App Links + iOS Universal Links intact).

**Referrals** — `/r/*` end-to-end 8/8 via the Pages `_redirects` rule → API → site, final 200.
Without that rule (added in `2367adc`) every referral link would have 404'd at apex cutover.

**Admin** — canonical entry point is Heroku:
`https://wtm-admin-…herokuapp.com/mood-ops-console-7x9` → 307 → login. The old apex route was
deliberately **not** recreated.

## 4. Soak log

### Checkpoint 1 — 2026-07-20 17:16Z (elapsed 4h41m / 48h)

| Signal | Result |
|---|---|
| API availability | `/healthz` `/readyz` `/v1/health` all **200** (0.29–0.90 s) |
| 5xx errors | **none** observed |
| Heroku crashes / restarts | **none** — `web.1 up`, single dyno since the 11:56Z config restart |
| Heroku memory (R14/R15) | **no R14/R15/H1x signatures** in the log window |
| Azure Job failures | **0 failures across all 9 jobs** |
| Recovery executions | **56 Succeeded** (`*/5`, exactly on schedule) |
| Cron executions | `daily-push` 5 ✅, `giveaway-chats` 5 ✅ (hourly). `news`/`spend-alert` next 18:00Z, `backup`/`credit-reset` next 00:00Z — **not yet due, correctly idle** |
| Queue backlog | **none** — `wardrobe_items` all `done=28` |
| Stranded / stale rows | **0 stranded queued, 0 stale processing** |
| Database connections | **14 / 60 = 23 %** (active 1, idle 6) |
| Website / HTTPS / legal / 404 | all **pass** |
| Referrals `/r/*` | end-to-end **200**, 2 hops |
| Deep-link files | **200 `application/json`, 0 redirects** |
| Data integrity | `wardrobe_items=28`, `auth.users=27` — baseline exactly |
| DO rollback env | `api`+`caddy` running, untouched |

**Verdict: no issues. Rollback not required.**

> ⚠ **Traffic caveat.** No try-on/AI jobs in 24 h, no rembg executions, and no router status
> lines — the soak is running at **near-zero real user load**. It therefore validates
> *infrastructure* stability (uptime, scheduling, recovery, connections, TLS, routing) but does
> **not** by itself validate the real user paths. Those depend on the owner's manual live-app
> test, which is **still outstanding**.

## 5. Outstanding before this phase can close

1. **Owner's manual live-app test result — not yet received.** Required to validate auth,
   uploads, background removal, AI try-on, credits and notifications on real devices.
2. **Remaining soak time** — ~43 h as of checkpoint 1.
3. **Not yet exercised during the soak** (schedule, not defects): `news`, `spend-alert`
   (next 18:00Z) and **`backup`, `credit-reset` (next 00:00Z)**. The nightly **backup** job in
   particular has not run once on Azure in production — confirm it succeeds at 00:00Z.

## 6. Standing risks carried into Phase 7

- **⚠ ACM renewal.** The `api.wearthemood.com` certificate expires **2026-10-18**. Initial
  issuance **failed while the Cloudflare proxy was on** and only succeeded grey-clouded. The
  proxy is now back on, so Heroku's automatic renewal (~30 days prior) may fail the same way —
  **silently** — until the cert expires. Monitor `heroku certs:auto`, or move to a Cloudflare
  Origin certificate with Full (strict). **Do not leave unmonitored.**
- **`GIT_SHA` cosmetic drift.** `/readyz` reports `17a3a8c` while the running image is
  `0851595`. The stamp step is now in the workflow and self-corrects on the next deploy.
- **DO admin container** has been `exited` since 2026-07-18 (pre-existing). Admin now runs on
  Heroku; no action needed beyond awareness.

## 7. Rollback readiness (verified, unchanged)

```bash
# API  — restore record 0bf9fe21… on zone wearthemood.com
{"type":"A","name":"api.wearthemood.com","content":"159.65.248.247","proxied":true,"ttl":1}
# SITE — restore record 70724268…
{"type":"A","name":"wearthemood.com","content":"159.65.248.247","proxied":true,"ttl":1}
# Then: disable Azure schedules, restart the DO worker plane
for j in wtm-prod-recovery wtm-prod-cron-{news,daily-push,backup,credit-reset,spend-alert,giveaway-chats}; do
  az containerapp job update -g wtm-prod -n $j --cron-expression "0 0 31 2 *"; done
ssh root@159.65.248.247 'cd /root/fashionos && docker compose start worker ofelia'
```

Rollback is **compute-only** — Supabase US stays authoritative in both directions, so no data
is lost and no reverse migration is needed. The DO API and Caddy never stopped.
