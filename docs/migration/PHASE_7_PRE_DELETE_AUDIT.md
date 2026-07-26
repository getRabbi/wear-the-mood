# PHASE 7 — DIGITALOCEAN PRE-DELETION AUDIT

> Evidence record for permanently deleting DigitalOcean droplet **577335646 (`fashion-os`, nyc3, 159.65.248.247)**.
> Audit executed **2026-07-26**. **No DigitalOcean resource was deleted, created or modified by this audit**
> other than stopping application containers (reversible, and left stopped by design).
> No secret values appear in this file.

---

## 0. Verdict

**The droplet can be deleted.** Every service it once ran has a verified live replacement, it received
zero required production traffic for six days, it holds no unique data, and production was proven
fully healthy through a 61-minute controlled blackout in which the droplet was completely dark.

Two genuine blockers were found and fixed during the audit (§9). One documentation error was found
and corrected (§5.1) — the DigitalOcean snapshot referenced by every rollback document **never existed**.

---

## 1. Real current state (documentation was stale — this section supersedes it)

`MIGRATION_STATE.md`'s "Current position" row still read *"Phase 6 IN PROGRESS — candidates only"*
and *"⛔ CUTOVER ATTEMPTED AND ROLLED BACK"*. That is **wrong**. The cutover succeeded on
2026-07-20 (the change log further down the same file records it correctly), the 48-hour soak
elapsed, and five weeks of feature work have shipped on `main` since.

### 1.1 Verified production inventory (2026-07-26)

| Component | Live target | Evidence |
|---|---|---|
| **API** | Heroku `wtm-api-prod` **v16**, Basic ×1, commit `78e7040` | `api.wearthemood.com` → `via: 2.0 heroku-router`; `/healthz` `/readyz` `/v1/health` all **200**, `readyz` `db:true environment:prod` |
| **API TLS** | Heroku ACM `melanorosaurus-27035`, CN `api.wearthemood.com`, **expires 2026-10-18** | `heroku certs` |
| **Website** | Cloudflare Pages project `wtm-site`, production branch `main` | project domains = `wtm-site.pages.dev, wearthemood.com, www.wearthemood.com` |
| **Admin** | Heroku `wtm-admin` (Eco ×1) | `/mood-ops-console-7x9` → **307** → `/login` **200**; root **404** by design |
| **Database** | Supabase **US `ghzabbceoaoertatkjyg`** (us-east-1), PostgreSQL 17.6 | 34 `auth.users` = 34 `profiles` = 34 `credits`, 0 orphans |
| **Storage (writes)** | **Cloudflare R2** (`STORAGE_WRITES=r2`) — `fashionos-private` / `fashionos-public`, CDN `cdn.wearthemood.com` | presigned PUT verified live |
| **Storage (legacy reads)** | Supabase Storage — 5 buckets, 684 objects | still authoritative for 43 pre-R2 rows |
| **Queue** | Azure Storage Queues `jobs` + `enrichment` on `wtmprodq4k2n8` | both **0 messages** |
| **Background removal** | Azure Container Apps Job **`wtm-rembg-job`** — event-triggered, 4 vCPU / 8 GiB, maxExec 1 | image `ghcr.io/getrabbi/wtm-rembg-worker@sha256:ae266423…` |
| **AI worker** | Azure Job **`wtm-ai-orchestrator-job`** — event-triggered, 0.5 vCPU / 1 GiB | image `ghcr.io/getrabbi/wtm-orchestrator@sha256:1625c973…` |
| **Recovery** | Azure Job `wtm-prod-recovery`, `*/5 * * * *` | 100 executions, 0 failures |
| **Scheduled jobs** | Six Azure `wtm-prod-cron-*` (news, daily-push, backup, credit-reset, spend-alert, giveaway-chats) | all enabled on their intended cron, all Succeeded |
| **Android production config** | `app/env/prod.json` → `API_BASE_URL=https://api.wearthemood.com`, US Supabase | release APK **1.0.14+16** and AAB scanned: **0 occurrences** of the droplet IP |

### 1.2 Background-removal model — correction to the audit brief

The brief asked to *"verify full U2Net is active, not U2NetP."* **Neither is active.** Production
runs **BiRefNet General Lite** (`BG_MODEL=birefnet-general-lite`, `BG_MASK_PIPELINE_V2=true`,
`REMBG_BATCH_MAX_JOBS=1`) — a deliberate upgrade deployed 2026-07-23, canary-passed, and merged to
`main` in PR #5. The U2Net expectation in the brief is stale. This is the intended state, not a defect;
the rollback image (u2net, `sha256:12016768…`) is still in GHCR.

---

## 2. DigitalOcean account inventory (read-only; nothing deleted)

Account `da427cff-5c62-4924-a6fd-d87508f5c429`, status `active`, droplet limit 3.
**Billing: all invoices $0.00**, including the current-month preview — the account runs on credits,
so the droplet currently costs nothing and deletion realises no immediate saving. It removes future
exposure when credits lapse.

### A. Proposed for deletion

| Field | Value |
|---|---|
| **Droplet ID** | **577335646** |
| Name | `fashion-os` |
| Region | `nyc3` |
| Size / spec | `s-2vcpu-4gb` — 2 vCPU, 4096 MB, 80 GB disk |
| Public IP | **159.65.248.247** |
| Created | 2026-06-13T05:34:06Z |
| Project | `fashionos` (`f2f14004-…`) — the droplet is the project's only resource |
| Tags | none |
| Auto-backups | **DISABLED** |
| Attached volumes | **none** |
| Monitoring agent | none configured |

### B. Remains after deletion — DO NOT DELETE

| Resource | ID / value | Note |
|---|---|---|
| **Droplet `ubuntu-s-1vcpu-1gb-nyc1`** | **568022411**, IP `165.22.12.123`, nyc1, created 2026-04-29 | **UNRELATED to Wear The Mood** — predates it, lives in the default `first-project`. Leave alone. |
| Firewall `fashionos` | `b3e82b7c-c4e5-447f-94d4-01e4ea161215` | attached to 577335646; becomes orphaned (empty) on deletion — free |
| Firewall `fashionos1` | `a3cdd5f4-a9f5-4c79-90c4-8b81391c29be` | same |
| Project `fashionos` | `f2f14004-b009-4647-9c24-75d29bc965b6` | becomes empty — free |
| Project `first-project` | `832c2bd5-…` (default) | holds droplet 568022411 |
| Project `tarka-ai` | `8fe63304-…` | already empty |
| SSH key `rabbi-windows-laptop` | `55972526` | free |
| VPCs `default-nyc3`, `default-nyc1` | defaults | free |

### C. Separately billable after droplet deletion

Exactly **one**: **droplet `568022411` (`ubuntu-s-1vcpu-1gb-nyc1`, `165.22.12.123`)** — list price
~$6/mo, currently $0 under account credit. Everything else in the account (firewalls, projects, VPCs,
SSH keys) is free of charge.

**Confirmed absent — nothing else can bill:** snapshots (0), droplet backups (0), volumes (0),
volume snapshots (0), reserved/floating IPs (0), load balancers (0), DigitalOcean DNS zones (0),
monitoring alert policies (0), uptime checks (0), container registry (404 — none), Kubernetes (0),
managed databases (0), App Platform apps (0), Spaces keys (404 — none), CDN endpoints (0).

---

## 3. What was running on the droplet, and its replacement

Compose project `fashionos` at `/root/fashionos`, five services. **No custom systemd units or timers,
no root crontab, no user crontabs, no `/etc/cron.d` entries, no monitoring agent, no webhook receiver,
no SSH tunnel** — verified.

| DO service | State at audit start | Replacement | Proven by |
|---|---|---|---|
| `api` | **running** (started 2026-07-18) | Heroku `wtm-api-prod` v16 | `via: 2.0 heroku-router`, 3× health 200 |
| `caddy` | **running** (started 2026-07-14) | Cloudflare (TLS + Pages) + Heroku ACM | apex + api both 200 with droplet dark |
| `worker` | exited 6 days (2026-07-20T12:27:18Z) | Azure `wtm-rembg-job` + `wtm-ai-orchestrator-job` | live cutout + try-on during blackout |
| `ofelia` | exited 6 days (2026-07-20T12:27:08Z) | 6 Azure `wtm-prod-cron-*` + `wtm-prod-recovery` | all Succeeded, effects verified |
| `admin-web` | exited 8 days (2026-07-18T17:10:43Z) | Heroku `wtm-admin` | `/mood-ops-console-7x9` 307→login 200 |

Docker volumes: `caddy-data` (Let's Encrypt certs — superseded, regenerable), `caddy-config`
(autosave), `rembg-models` (`u2net.onnx`, 167.9 MB — a public model, and no longer the production
model). **No volume holds user data.**

Every prohibited residual function is accounted for: no process on the droplet handles production
requests, polls the DB, processes background removal or AI jobs, sends notifications, creates
newsroom content, resets credits, creates giveaway chats, performs backups, raises spend alerts,
receives store/payment webhooks, hosts legal pages, handles referrals, or serves admin functions.

---

## 4. Unique-data audit — nothing authoritative remains

**Decisive finding: zero files under `/root/fashionos` are newer than the 2026-07-18 encrypted backup**
(excluding `.env*` and `backups/`, both captured in the decommission bundle). The newest source file
is dated 2026-07-15.

| Candidate | Finding | Where it already lives |
|---|---|---|
| User uploads / wardrobe / cutouts / try-on results / community images | **None on disk** — no uploads/media/storage directory exists | Supabase Storage (684 objects) + R2 |
| Database | No database runs on the droplet | Supabase US |
| Code | `/root/fashionos` is **not a git checkout** (file-sync deploy); migrations stop at `0043` while the repo has `0044`–`0048` | GitHub `getRabbi/wear-the-mood`, tag `pre-migration-20260718` → `98df3c3` (on origin) |
| Container images | Local builds only | GHCR — both Azure-pinned digests confirmed present |
| Website files | `deploy/site` (16 files) | Cloudflare Pages + Git |
| Secrets / config | 13 `.env*` files | **Captured in the decommission bundle (§5.2)** + Phase 1 backup |
| Loose DB dumps | `backups/prod/2026-07-15T…_pre_0043.sql` ×2 (1.8 MB) | **Captured in the decommission bundle** |
| Loose archives in `/root` | 6 `.tgz`/`.tar.gz` + 3 dirs — all historical **backend source-tree** snapshots (Jun 17–26) | In Git; **also captured in the bundle** for completeness |
| Certificates | Caddy LE certs for the 3 hostnames | Superseded by Heroku ACM + Cloudflare; regenerable |

**Database cross-check:** all 231 text/varchar columns in the `public` and `storage` schemas were
scanned for `159.65.248.247`, `digitalocean`, `ondigitalocean`, `fashion-os` — **0 hits**. Zero
function bodies and zero views reference DigitalOcean.

---

## 5. Backups

### 5.1 ⚠ CORRECTION — the DigitalOcean snapshot never existed

`BACKUP_MANIFEST.md` and `ROLLBACK_RUNBOOK.md` both list DO snapshot **`wtm-pre-migration-20260718`**
as a retained safety asset ("owner-confirmed complete 2026-07-18"). **It does not exist and never did.**

Evidence: `/v2/snapshots` = 0 · `/v2/snapshots?resource_type=droplet` = 0 · `/v2/droplets/577335646/snapshots`
= 0 · `/v2/droplets/577335646/backups` = 0 · `/v2/images?private=true` = 0 · and conclusively, the
**droplet's complete lifetime action history is 4 actions** — `create` (2026-06-13), `power_off`,
`resize`, `power_on` (all 2026-06-22). **No `snapshot` action was ever issued.**

**Owner decision (2026-07-26): do not create a replacement snapshot**, on the basis that the verified
R2 archive plus the decommission bundle already contain everything a snapshot would (and the droplet
holds nothing newer than the archive). Recorded as an accepted, evidenced decision.

### 5.2 Verified safety assets

| Asset | Status |
|---|---|
| **Phase 1 encrypted archive** `r2://fashionos-private/migration-backups/2026-07-18/wtm-phase1-backup-20260718.tar.gpg` | ✅ **Re-verified this audit** — 84,004,944 bytes streamed and hashed: SHA-256 `9b4f7b59458cdc30cde8c70d762cda379d749875e6089e7bfee6c35acf9f1e4e`, **exact match** to the manifest. Header `8c0d0409…` = valid OpenPGP AES-256 symmetric packet. Contains DB roles/schema/data (incl. `auth.users`), 120 Storage objects, droplet config, full git bundle. |
| **Git tag** `pre-migration-20260718` → `98df3c3` | ✅ present locally **and on `origin`** |
| **GHCR images** | ✅ both digests Azure pins are present: `wtm-rembg-worker@sha256:ae266423…` (tag `6093f86-birefnet-general-lite`), `wtm-orchestrator@sha256:1625c973…` |
| **Nightly DB backups** | ✅ Azure `wtm-prod-cron-backup` has written a dump every day 2026-07-20 → 2026-07-26 to `r2://fashionos-private/backups/prod/`; a manual run during the blackout produced `20260726T193733Z.dump` and retention pruned the oldest (steady state: 7) |
| **DigitalOcean snapshot** | ❌ **does not exist** — see §5.1 |

### 5.3 Final decommission bundle

Collected from the live droplet on 2026-07-26 before the blackout.

| Field | Value |
|---|---|
| Plaintext tar | `/root/wtm-decommission-config-20260726.tar` |
| Bytes | 3,727,360 |
| Plaintext SHA-256 | `3fe3f64c831317a518b8787ab26cd9816260dd50f6192a32c8c9d1fb59412632` |
| Files | 89 |
| Sections | `compose/` (3) · `caddy/` (3) · `systemd/` (4) · `cron/` (4) · `env/` (13) · `docker/` (12) · `inventory/` (11) · `deploy/` (18) · `db-dumps/` (4) · `legacy-archives/` (15) · plus `FILELIST.txt` + `SHA256SUMS.txt` |
| Contents | `docker-compose.yml` + rendered config, `Caddyfile` + Caddy autosave + cert inventory, full systemd unit/timer/enabled-unit listings, every crontab + `/etc/cron.*` + the ofelia schedule labels, **all 13 `.env*` files**, `docker inspect` for all 5 containers + images/volumes/networks/version/info, `uname`/`os-release`/`dpkg -l`/listening ports/ufw/iptables/df/free/DO metadata, the static site + legal sources, the 2 loose pre-`0043` SQL dumps, and all historical `/root` archives |
| Encryption | `gpg --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512`, freshly generated 40-char random passphrase (owner's choice, 2026-07-26). Passphrase generated on the droplet in `tmpfs`, never written to disk, shredded immediately after use, and **never committed to this repo**. It was delivered to the owner once, out of band. |
| Encrypted artifact | see §5.4 |

**Contains plaintext secrets by design** — that is precisely why it is encrypted before leaving the
droplet, and why it is stored only in the private R2 migration-backup prefix.

### 5.4 Encrypted upload record — ✅ COMPLETE

| Field | Value |
|---|---|
| **R2 path** | `r2://fashionos-private/migration-backups/2026-07-26/wtm-decommission-config-20260726.tar.gpg` |
| **Encrypted SHA-256** | `ac9a50643b2ef02ba0b4bf030cddd1e1fe645650680b469007fa5da7dcf6db22` |
| Encrypted bytes | 2,050,481 |
| Plaintext SHA-256 | `3fe3f64c831317a518b8787ab26cd9816260dd50f6192a32c8c9d1fb59412632` (3,727,360 bytes, 89 files) |
| **Created (UTC)** | **2026-07-26T20:04:29Z** — uploaded 2026-07-26T20:06:40Z |
| Cipher | OpenPGP symmetric, `cipher 9` (AES-256), `s2k 3`, `hash 10` (SHA-512), salt `44EBDE583557B24A`, count 65011712 |

**Verification performed (all passed):**

1. **Full decrypt round-trip on the droplet** — the ciphertext was decrypted with the passphrase and
   the plaintext re-hashed: `3fe3f64c…` == the original tar's SHA-256. **Exact match.**
2. **Structural check** (`gpg --list-packets`, no passphrase required) — `tag=3 :symkey enc packet:
   version 4, cipher 9, s2k 3, hash 10`, followed by `tag=18` (AEAD/MDC-protected data). A
   well-formed AES-256 symmetric OpenPGP file.
3. **Transfer integrity** — the copy pulled from the droplet hashed to `ac9a5064…`, identical to the
   droplet's own hash.
4. **R2 round-trip** — the object was re-downloaded from R2 in full (2,050,481 bytes) and re-hashed:
   `ac9a5064…`. **Byte-for-byte identical** to what was uploaded, and to the artifact whose decrypt
   round-trip was proven in step 1.

**Cleanup after upload:** the passphrase file was shredded from `tmpfs`, and the plaintext tar,
the staging directory and the collector/encryptor scripts were deleted from the droplet. Only the
encrypted artifact remains there (and it is redundant with R2). The local copy and the temporary
DigitalOcean API token file were deleted from the workstation scratchpad.

**`migration-backups/` prefix now holds exactly two objects:**

| Object | Bytes | Created |
|---|---|---|
| `2026-07-18/wtm-phase1-backup-20260718.tar.gpg` | 84,004,944 | 2026-07-18T05:03:23Z |
| `2026-07-26/wtm-decommission-config-20260726.tar.gpg` | 2,050,481 | 2026-07-26T20:06:40Z |

---

## 6. Nothing points to DigitalOcean

| Surface | Result |
|---|---|
| Tracked source (non-doc) | **1 hit**: `app/build_prod.ps1:26` `$DO_IP = "159.65.248.247"` — used **only as a negative guard** (rejects a build whose `API_BASE_URL` points at the droplet). It keeps working after deletion. Retained deliberately. |
| Documentation | 24 historical references across `docs/migration/*`, `infra/cloudflare/route-plan.md`, `docs/bg/*` — permitted as historical evidence |
| Flutter prod config | `app/env/prod.json` → `https://api.wearthemood.com`; no DO reference |
| **Release APK 1.0.14+16** | scanned every `.so`/`.dex`/`.arsc`/`.json`/`.xml`: **DO IP ×0**, Tokyo Supabase ×0, `ondigitalocean` ×0, `herokuapp.com` ×0; `api.wearthemood.com` ×3, US Supabase ×18 |
| **Release AAB** | **DO IP ×0**, Tokyo ×0, `ondigitalocean` ×0; `api.wearthemood.com` ×6, US Supabase ×36 |
| Heroku config (45 vars) | no DigitalOcean host, IP or endpoint in any name or value |
| Azure job env (54 vars) | no DigitalOcean reference; queue/storage/DB all point at Azure/R2/Supabase US |
| GitHub Actions | repo secret `LOADTEST_USERS_JSON`; environment `production` holds `HEROKU_API_KEY`, `HEROKU_EMAIL`. No DO secret, no DO deploy step, no `ssh root@` in any workflow |
| Codemagic | `API_BASE_URL` injected from the `app_prod_config` env group (`https://api.wearthemood.com`); no DO reference |
| **Cloudflare DNS** | **no record resolves to 159.65.248.247**. `api.wearthemood.com` and `wearthemood.com` both resolve to Cloudflare proxy IPs `104.21.28.58` / `172.67.170.99`; origins are Heroku and Pages respectively |
| Cloudflare Pages rules | `_redirects` routes `/r/*` to the Heroku API; no origin rule references DO |
| **Supabase hooks/functions** | **no `supabase_functions` schema, no `pg_cron`, no `net` extension** — the database cannot make outbound calls at all |
| RevenueCat webhook | the droplet API's **entire** log history (2026-07-18 → 2026-07-26) contains **0** webhook/billing requests; the webhook target hostname `api.wearthemood.com` now resolves to Heroku |
| FCM / auth redirects | push is server-initiated (`PUSH_PROVIDER=fcm` on Heroku + Azure); auth redirects target `wearthemood.com` (Pages) |
| Monitoring / uptime | **zero** DO monitoring alert policies and **zero** DO uptime checks exist; no external monitor reached the droplet (§8) |

---

## 7. Replacement platform verification

**API** — `api.wearthemood.com` served by Heroku (`via: 2.0 heroku-router`); `/healthz` 200,
`/readyz` 200 `db:true environment:prod commit:78e7040`, `/v1/health` 200. 91 documented paths.
Weather (`/v1/weather/current`, `/v1/weather/geocode`) deployed and returning live Open-Meteo data.
Community `author_avatar_url` present and populated in the feed payload. `enhance_cost: 4` returned by
`/v1/credits`. `QUEUE_PROVIDER=azure` with both queue names set. No DigitalOcean endpoint in config.

**Website** — Cloudflare Pages. `/` 200 · `/legal/privacy` `/legal/terms` `/legal/acceptable-use` 200
(extensionless) · `/delete-account` 200 · `/invite/` 200 · `/r/<code>` → 302 → API → 200 ·
`assetlinks.json` and `apple-app-site-association` both **200 `application/json`, 0 redirects** ·
unknown paths return a **real 404** (the soft-404 noted in Phase 6 is fixed) · `/mood-ops-console-7x9`
on the apex returns 404, so the admin is not exposed there.

**Admin** — Heroku `wtm-admin`. `/mood-ops-console-7x9` → 307 → `/login` → 200. No admin route
depends on the droplet.

**Database / storage** — Supabase US authoritative. 34 users = 34 profiles = 34 credits, 0 orphan
profiles, 0 users without a profile. Signup trigger **`on_auth_user_created` → `handle_new_user`
present and enabled**. All 5 storage buckets exist with correct public flags; **20 RLS policies** on
`storage.objects`. No runtime uses a droplet-local database. No required media is served only from
the droplet.

---

## 8. DigitalOcean traffic — zero required production traffic

**The strongest single piece of evidence in this audit.** The droplet's API container logs every
request (uvicorn access log). Over its entire life:

- Container started **2026-07-18T17:10:48Z**, 605 log lines total.
- **Last request of any kind: `2026-07-20T13:04:06Z`** — the day of cutover, a `/r/TESTCODE` probe.
- **Zero requests between 2026-07-20T13:04:06Z and the blackout**, a span of **6 days 5 hours**.
- The logger was proven still live: an audit probe at **2026-07-26T18:29:20Z** appeared immediately as
  line 606. So "zero lines" means zero requests, not a broken logger.
- That probe returned **404** for `/healthz` — the droplet runs pre-cutover code that predates the
  endpoint, further confirming it is not the live API.

All pre-cutover app traffic (190 `PUT /v1/profile/push-token`, 38 `GET /v1/wardrobe`, 37 `/v1/profile`,
37 `/v1/outfits`, 36 `/v1/flags`) stops dead at the cutover timestamp.

**Bot vs legitimate traffic:** Caddy has no `log` directive, so it records only ACME/TLS maintenance
(52 lines in 48 h, all cert-renewal bookkeeping). Port 80/443 DNAT counters showed ~13.5k/10.1k packets
across 12 days of Caddy uptime — background scanning noise. The same scanner population is visible in
the Heroku router log hitting `api.wearthemood.com` (`/vendor/phpunit/…/eval-stdin.php`,
`/sftp-config.json`, `/.env`, `/admin/filemanager/dialog.php`), and the droplet's own log shows the
identical pattern (`/.env`, `/_profiler/phpinfo`, `/terraform.tfstate`, `/serviceAccountKey.json`).
**No legitimate client, monitor, webhook or scheduled process reached the droplet.**

---

## 9. Blockers found and fixed

### 9.1 FIXED — published privacy policy named DigitalOcean as the hosting sub-processor

`https://wearthemood.com/legal/privacy` §4 declared *"Cloud hosting — DigitalOcean (cloud hosting)"*
and omitted Heroku, Microsoft Azure and Cloudflare, all of which now process user data. That
disclosure has been inaccurate since 2026-07-20 and would be plainly false after deletion — a GDPR
Art. 13 / Play Data Safety accuracy problem, not merely cosmetic.

**Fix:** `deploy/build_legal.py` `HOSTING_REGION/PROVIDER` updated to
*"Heroku (Salesforce) — API hosting, United States; Microsoft Azure — background AI/image processing,
Asia Pacific; Cloudflare — CDN, image storage and static site hosting"*; legal HTML regenerated and
deployed to Cloudflare Pages production (deployment `89d8d3d6`).
**Re-verified live** — the corrected line is served, and all site checks re-run clean (§7).

### 9.2 FIXED (documentation) — non-existent snapshot recorded as a retained safety asset

See §5.1. Every rollback path in the repo pointed at a full-disk snapshot that was never taken.
`BACKUP_MANIFEST.md` and `ROLLBACK_RUNBOOK.md` corrected in this commit.

### 9.3 Not blockers — assessed and dismissed

- `app/build_prod.ps1` `$DO_IP` — a negative guard, unaffected by deletion.
- 25 `wardrobe_items` carry a stale `cutout_locked_at`, but **all 53 are `cutout_status='done'`** and
  the worker's claim predicate excludes `done`, so none is actionable.
- 43 wardrobe rows still hold `supabase.co` media URLs — legacy pre-R2 objects served by Supabase
  Storage, which remains live. Not a droplet dependency.
- `wtm-rembg-job` shows 3 `Stopped` executions, all on 2026-07-20 08:12–08:55Z — the deliberate
  Phase 6 replica-kill recovery tests, pre-cutover and resolved. Zero unresolved failures since.

---

## 10. Controlled blackout test

| Field | Value |
|---|---|
| **Start** | **2026-07-26T18:47:58Z** |
| **End (verified)** | **2026-07-26T19:48:57Z** |
| **Duration** | **61 minutes** (minimum 60) |
| Preparation | `docker update --restart=no` applied to **all 5** containers first, so nothing could self-heal |
| Stopped | `api`, `caddy`, `worker`, `ofelia`, `admin-web` — the complete compose project |
| Listening after stop | **no application port** — only `sshd:22` and `systemd-resolved` on loopback |
| Droplet reachability | `http://159.65.248.247/` → `000`, `https://159.65.248.247/` → `000`, apex-SNI → `000` |
| SSH | left available throughout for rollback |
| **Rollback needed** | **none** |
| Post-blackout | DO services **left stopped**, per protocol |

### During the blackout

- **Production endpoints:** API `/healthz` `/readyz` `/v1/health`, apex `/`, all three legal pages,
  `/delete-account`, both `.well-known` files, `/r/*` chain, and the admin login — **all 200/307 at
  T+0 and again at T+61**.
- **Heroku:** 0 H-codes (H10/H12/H13), 0 R14/R15, **0 dyno restarts**, **0 5xx**. `web.1` up 23 h
  continuously — it never noticed.
- **Azure:** 17 executions fired inside the window (9 recovery, 1 daily-push, 1 giveaway-chats,
  2 rembg, 4 orchestrator) — **0 failures**.
- **Queues:** `jobs` and `enrichment` both drained to **0**.
- **Stale rows:** 0 wardrobe items needing cutout, 0 `tryon_jobs` queued/processing, 0 `ai_jobs`
  queued/processing — before, during and after.
- **All replacement scheduled jobs manually triggered and verified** (§11).
- **Full authenticated user-flow smoke test passed** (§12).

---

## 11. Scheduled jobs — manual trigger + effect verification (during blackout)

| Job | Schedule | Manual run | Verified effect |
|---|---|---|---|
| `wtm-prod-cron-news` | `0 */6 * * *` | Succeeded, 105 s | `news_items` 1732 → 1734; newest `created_at` moved 18:01:19Z → **19:36:21Z** |
| `wtm-prod-cron-backup` | `0 0 * * *` | Succeeded, 129 s | new dump **`backups/prod/20260726T193733Z.dump`** in R2; retention pruned the oldest (steady state 7) |
| `wtm-prod-cron-credit-reset` | `0 0 * * *` | Succeeded, 28 s | — |
| `wtm-prod-cron-credit-reset` (**2nd run**) | idempotency probe | Succeeded, 42 s | **credits rows Δ0, balance sum Δ0** — no duplicate grant |
| `wtm-prod-cron-spend-alert` | `0 */6 * * *` | Succeeded, 41 s | — |
| `wtm-prod-cron-spend-alert` (**2nd run**) | idempotency probe | Succeeded, 40 s | no duplicate effect |
| `wtm-prod-cron-daily-push` | `0 * * * *` | fired on schedule 19:00Z | Succeeded |
| `wtm-prod-cron-giveaway-chats` | `0 * * * *` | fired on schedule 19:00Z | Succeeded |
| `wtm-prod-recovery` | `*/5 * * * *` | 9 fired on schedule | all Succeeded |

Trailing-7-day failure count across all nine jobs: **0** (excluding the three intentional 2026-07-20
replica-kill `Stopped` executions).

---

## 12. Live user-flow smoke test (droplet dark)

One synthetic user (`wtm-p7-audit-…@example.com`), created and deleted within the window.
**Server-side equivalent of the app flows** — see §13 for what was not tested on-device.

| Flow | Result |
|---|---|
| Email login (password grant) | ✅ 200 |
| New-account profile + credits via signup trigger | ✅ profile + credits auto-created; `total_available: 3`, `enhance_cost: 4` |
| Biometric consent | ✅ 201 |
| Presigned R2 upload — garment / profile pic / try-on photo | ✅ 3× `upload-url` + PUT 200 |
| Profile photo change | ✅ `PATCH /v1/profile` 200 |
| Wardrobe create → queue signal | ✅ 201, `cutout_status=queued` |
| **Azure BiRefNet background removal** | ✅ queued → processing (44.6 s) → **done at 66.2 s**; execution `wtm-rembg-job-d2dld` 18:55:04→18:56:55Z |
| Cutout output integrity | ✅ `attempt_count=1` (single claim, no double-processing); exactly one each of original / cutout / thumb / cutout-mask in R2 — **no duplicates** |
| **AI try-on** (1 paid FASHN call) | ✅ 202 → done in **54.8 s**; exactly **1 credit** deducted (`daily_free_used` 0→1) |
| AI result Save | ✅ `/v1/tryon/results` 200, n=1 |
| AI Enhance gating | ✅ free tier correctly blocked **402 PAYWALL** ("Unlock AI Studio with Pro or Pro Max") — designed behaviour |
| **AI Enhance deducts 4 credits** | ✅ after elevating to Pro: reserve-at-submit Δ4, final Δ**4**, job `completed` in 65.3 s, output produced |
| **Failed AI action refunds** | ✅ proven from real production history — all 4 `failed` `ai_jobs` have `credits_reserved=1, credits_charged=0`; all 18 completed have reserved==charged (27==27); **zero failed-but-charged rows** |
| Community post + feed + `author_avatar_url` | ✅ 201; own post in feed; `author_avatar_url` **present and populated** |
| Comment + like | ✅ 201 / 204 |
| Real weather | ✅ `/v1/weather/current` 200 — live Open-Meteo (`26.5 °C`, "Partly cloudy", humidity 87); `/v1/weather/geocode` 200 |
| Stylist with weather context | ✅ 200, wardrobe-aware rationale |
| Notifications | ✅ list 200, 7 preference categories 200, push-token registration 204 |
| Referrals | ✅ `/v1/referrals/me` 200 → code `HKK5DGRV`; public `https://wearthemood.com/r/HKK5DGRV` → **302** → API |
| Flags / news / guide / entitlement | ✅ all 200; news n=20 (Azure cron output) |
| **Session restart** (refresh-token grant) | ✅ 200; authenticated calls and wardrobe still work |
| Data export | ✅ 200, 4,375 bytes |
| **Account deletion + residue** | ✅ 204; **0 rows** in `auth.users`, `profiles`, `credits`, `consents`, `wardrobe_items`, `posts`, `tryon_jobs`, `ai_jobs`, `user_subscriptions`, `device_tokens`; **0 R2 objects** remain |

**Post-audit baseline restored exactly:** 34 `auth.users` / 34 profiles / 34 credits / 53 wardrobe
items / 31 `tryon_jobs` / 20 `ai_jobs`, 0 orphan profiles, 0 actionable work. Paid spend for the whole
audit: **1 FASHN try-on (~$0.075)** + 1 AI Enhance, both on synthetic data.

---

## 13. Explicit disclosure — not tested on-device

No Android device was attached during this audit. Everything above is server-side or
artifact-level evidence. Specifically **not** verified on hardware:

- On-device rendering of any screen.
- **Actual delivery of an FCM push to a handset** (registration returns 204 and the Azure
  `daily-push` job succeeds hourly, but end-to-end delivery to a physical device remains the
  standing manual owner step).
- Google Play Billing purchase UX (RevenueCat sandbox).
- App Links / Universal Links opening the installed app (the `.well-known` files serve correctly with
  the right content type and no redirect, which is the server-side half).

This is acceptable per the audit's own criterion: the already-built production APK **1.0.14+16** and
AAB were byte-scanned and contain **only** the live production domain, with **zero** occurrences of
the droplet IP — so no on-device path can reach DigitalOcean.

---

## 14. Rollback posture after deletion

**DigitalOcean is no longer a rollback path.** See the rewritten `ROLLBACK_RUNBOOK.md`. Recovery is
now rebuild-and-redeploy from Git + GHCR + the encrypted R2 backups. There is no warm standby, and
after deletion there is no snapshot either (§5.1).

---

## 15. Status

Phase 7 is **NOT complete** and the droplet is **NOT deleted**. This document is the pre-deletion
evidence record only. Deletion requires the owner's `AUTHORIZE DIGITALOCEAN DECOMMISSION`.
