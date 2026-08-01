# Hotfix deploy runbook — AI Enhance, Giveaway requests/chat, Notifications

Release **1.0.19+22**, branch `fix/enhance-quality-giveaway-state-notifications`.

The four reported production issues already have fixes committed on this branch.
They are still visible to users because **the backend was never deployed and the
app was never released** — not because the code is wrong. This runbook ships them.

> **Scope of what was verified.** The deployment gap was proven by diffing the
> live OpenAPI against this branch (§1). The migration safety review is a read of
> the SQL (§3). Migration state on production **was** verified read-only on
> 2026-08-01 — see §3.1: **none of 0049–0052 are applied.**

---

## 0. Facts this runbook is built on

| Thing | Value | How it was established |
|---|---|---|
| API | Heroku `wtm-api-prod` | `via: 2.0 heroku-router` on `api.wearthemood.com` |
| Workers / crons | Azure Container Apps Jobs (`wtm-ai-orchestrator-job`, `wtm-prod-cron-*`) | `docs/migration/INFRASTRUCTURE_INVENTORY.md` |
| Database | Supabase US `ghzabbceoaoertatkjyg` | `MIGRATION_STATE.md`, `/readyz` |
| Deployed API commit | `5e4830a` | `/readyz` |
| DigitalOcean | **decommissioned — NOT a rollback path** | `MIGRATION_STATE.md` Phase 7 |

`DEPLOY_DIGITALOCEAN.md` and CLAUDE.md §2 are **stale**. Ignore them for this release.

### Both compute tiers must ship

This is the step most likely to be missed. The fixes span the API *and* the
background workers:

| Fix | `routers/` | `workers/` | `cron/` | Needs |
|---|---|---|---|---|
| `680deb8` AI Enhance source/MIME/credits | ✅ | ✅ | — | Heroku **+ Azure** |
| `41b650e` Giveaway + notifications | ✅ | — | ✅ | Heroku **+ Azure** |
| `fa51f31` Enhance race, push outbox | ✅ | ✅ | ✅ | Heroku **+ Azure** |
| `9605b4e` Google nonce, outbox settle | — | ✅ | ✅ | **Azure** |

**Deploying only the Heroku API leaves the AI-enhance worker on old code** — it
would keep sourcing the background-removed cutout, so Issue 1 would appear unfixed.

---

## 1. Pre-flight (5 min, read-only)

```bash
# 1.1  Confirm the gap still exists and nothing else drifted.
curl -s https://api.wearthemood.com/readyz
# expect: {"status":"ready","db":true,"environment":"prod","commit":"5e4830a", ...}

# 1.2  Confirm the two missing endpoints are still missing.
curl -s https://api.wearthemood.com/openapi.json \
  | python -c "import json,sys; p=json.load(sys.stdin)['paths']; \
      print('requested :', '/v1/giveaways/requested' in p); \
      print('post GET  :', 'get' in p.get('/v1/social/posts/{post_id}',{}))"
# expect: both False (before), both True (after)
```

Do **not** trust `commit` alone — `GIT_SHA` is a config var and has gone stale
before (observed at v5: the field said `17a3a8c` while the image was `0851595`).
The OpenAPI diff is the authoritative signal.

```bash
# 1.3  Branch is clean, pushed, and tests are green.
git status --porcelain          # empty
cd backend && ruff check . && ruff format --check . && pytest -q
cd ../app && flutter analyze && flutter test
```

---

## 2. Backup (owner, mandatory, ~10 min)

Migrations are additive, but take the backup anyway — it is the only real undo.

```bash
cd backend
# Uses CONNECTION_STRING_DIRECT (5432) from backend/.env.prod — see OPS_RUNBOOK.md §2.
pg_dump --format=custom --no-owner --no-privileges \
  -d "$CONNECTION_STRING_DIRECT" -f wtm-prod-$(date +%Y%m%d-%H%M).dump
```

Record the file name and size. Restore procedure: `OPS_RUNBOOK.md` §2.

---

## 3. Migrations 0049–0052 — why they are safe

Apply these **before** the code. They are additive, so the currently-running old
code simply ignores the new columns. The reverse order is what breaks: new code
reads `notifications.dedupe_key`, and deploying it against a database without
that column produces 500s on the notification path.

| Migration | What it does | Safety |
|---|---|---|
| `0049_giveaway_system_messages` | `create unique index if not exists`; `alter column sender_id drop not null` | A **relaxation** — every existing row still satisfies it |
| `0050_notification_pipeline` | `add column if not exists dedupe_key text`; `add column if not exists data jsonb not null default '{}'` | Additive; NULL `dedupe_key`s do not collide in the unique index |
| `0051_notification_outbox` | `create table if not exists notification_outbox` | New table only |
| `0052_outbox_delivery_outcomes` | `add column status`; backfill `set status='delivered' where delivered_at is not null and status='pending'`; index swap | Backfill is narrow, truthful and idempotent |

**No column drops, no table drops, no `DELETE`, no `TRUNCATE`.** The only two
`drop` statements are `drop index if exists` (replaced immediately by a better
index) and the `NOT NULL` relaxation above.

### 3.1 Verified production state (read-only, 2026-08-01)

**None of 0049–0052 are applied.** All four must run.

| Migration | State | Evidence |
|---|---|---|
| 0049 | **not applied** | `giveaway_chat_messages_system_once_idx` missing, `giveaway_chat_messages_chat_created_idx` missing, `giveaway_chat_messages.sender_id` still `NOT NULL` |
| 0050 | **not applied** | `notifications.dedupe_key` missing, `notifications.data` missing, `notifications_dedupe_idx` missing, `notifications_user_keyset_idx` missing |
| 0051 | **not applied** | table `notification_outbox` does not exist |
| 0052 | **not applied** | (depends on 0051) |

There is no migration-tracking table — `apply_all.py` re-runs the whole ordered
set idempotently — so state is inferred from the schema artifacts each migration
creates.

**One trap worth recording.** A naive probe reports 0049 and 0050 as *partially*
applied, because `giveaway_claims_claimer_idx` and `device_tokens_active_idx` are
both present. They are not from these migrations: they come from `0020_giveaways`
and `0043_notification_prefs_align_and_token_prune`, and 0049/0050 merely
re-declare them defensively with `create index if not exists`. Judge applied-ness
only by artifacts **unique** to the migration, or a re-run looks half-done when it
is simply not started.

This confirms the ordering requirement above is real, not theoretical: production
has no `notifications.dedupe_key`, so releasing the new API before step 4 would
500 the notification path immediately.

---

## 4. Apply migrations (owner)

Verified state as of 2026-08-01: **all four are outstanding** (§3.1). Re-confirm
immediately before applying, in case anything shipped in the meantime.

```bash
# 4.1  Re-confirm (read-only). Expect ZERO rows and "Did not find any relation".
psql "$CONNECTION_STRING_DIRECT" -c \
  "select column_name from information_schema.columns
    where table_name='notifications' and column_name in ('dedupe_key','data');"
psql "$CONNECTION_STRING_DIRECT" -c "\dt public.notification_outbox"

# 4.2  Apply. Idempotent — re-runs the whole ordered set including the baseline.
#      NOTE: use the LIVE credentials. backend/.env.prod is STALE and still points
#      at the decommissioned Tokyo project; applying against it would migrate the
#      wrong database and leave production untouched.
cd backend
heroku config -a wtm-api-prod --json \
  | python -c "import json,sys; c=json.load(sys.stdin); \
      print('CONNECTION_STRING_DIRECT=' + (c.get('CONNECTION_STRING_DIRECT') or c['CONNECTION_STRING']))" \
  > .env.prod.live          # git-ignored; delete afterwards
python scripts/apply_all.py .env.prod.live
rm .env.prod.live

# 4.3  Verify — expect dedupe_key AND data.
psql "$CONNECTION_STRING_DIRECT" -c \
  "select column_name from information_schema.columns
    where table_name='notifications' and column_name in ('dedupe_key','data');"
psql "$CONNECTION_STRING_DIRECT" -c \
  "select 1 from information_schema.tables where table_name='notification_outbox';"
```

---

## 5. Deploy the API (owner, gated)

GitHub → Actions → **migration-deploy** → *Run workflow*:

- **Branch:** `fix/enhance-quality-giveaway-state-notifications`
- **target:** `prod`

This requires approval on the protected `production` GitHub Environment. It
builds `backend/api.Dockerfile`, pushes to the Heroku container registry,
releases by immutable image id, then stamps `GIT_SHA` so `/readyz` tells the truth.

```bash
# Verify
curl -s https://api.wearthemood.com/readyz
# expect commit = the deployed short SHA, and local_cutout:"enabled"
curl -s https://api.wearthemood.com/openapi.json \
  | python -c "import json,sys; p=json.load(sys.stdin)['paths']; \
      print('requested :', '/v1/giveaways/requested' in p); \
      print('post GET  :', 'get' in p.get('/v1/social/posts/{post_id}',{}))"
# expect: both True
```

---

## 6. Deploy the workers and crons (owner) — DO NOT SKIP

GitHub → Actions → **migration-build** → *Run workflow* on the same branch. It
builds and pushes `wtm-orchestrator` (and the other images) to GHCR tagged with
the commit SHA.

Then point the Azure jobs at the new image:

```bash
az containerapp job update -g wtm-prod -n wtm-ai-orchestrator-job \
  --image ghcr.io/getrabbi/wtm-orchestrator:<commit-sha>

# Repeat for each wtm-prod-cron-* job that runs from the orchestrator image.
az containerapp job list -g wtm-prod -o table     # enumerate them first

# Confirm the next execution succeeds
az containerapp job execution list -g wtm-prod -n wtm-ai-orchestrator-job -o table
```

Pin the **digest**, not a floating tag, so a later rebuild cannot silently change
what is running.

---

## 7. Post-deploy verification

| # | Check | Expected |
|---|---|---|
| 7.1 | `/readyz` | `status: ready`, `db: true`, `local_cutout: "enabled"` |
| 7.2 | `/openapi.json` | both endpoints from §1.2 present |
| 7.3 | Giveaway → My Requests | loads; pending/accepted/rejected/cancelled all render |
| 7.4 | Two accounts: A creates, B requests, A accepts | **exactly one** conversation; both see it |
| 7.5 | Force-close and relaunch both | chat still visible |
| 7.6 | AI Enhance on 5 garment photos | fabric/stitching/print improved, garment identity unchanged; **one** job and **one** 4-credit transaction per tap |
| 7.7 | Enhance failure path | credits refunded in full |
| 7.8 | Notifications: request, accept, message, like, comment, follow | in-app row created; tap opens the correct destination; unread count refreshes |

7.3–7.8 are the acceptance criteria and **require two real accounts on real
devices**. They are not automatable from here.

---

## 8. Rollback

**Code** — additive migrations mean the old image runs fine against the new schema:

```bash
# API: re-release the previous Heroku release.
heroku releases -a wtm-api-prod          # find the last good version
heroku releases:rollback vNN -a wtm-api-prod

# Workers: repoint to the previous image digest.
az containerapp job update -g wtm-prod -n wtm-ai-orchestrator-job \
  --image ghcr.io/getrabbi/wtm-orchestrator@sha256:<previous-digest>
```

**Do not roll back the migrations.** They are additive; the old code ignores the
new columns. Dropping them would destroy notification history.

**Database** — only if data corruption is proven, and only from the §2 dump.
This is destructive and loses everything written since the backup.

**DigitalOcean is not a rollback path** — the droplet was decommissioned in place
on 2026-07-26 and served zero requests for six days before that.

---

## 9. App release (separate, after the backend is verified)

The signed artifacts already exist at commit `cc5ed30`, version **1.0.19+22**:

- APK `app/build/app/outputs/flutter-apk/app-release.apk` — `5fda8061…84fe6`
- AAB `app/build/app/outputs/bundle/release/app-release.aab` — `93cd449c…d5cef`
- IPA `Wear_The_Mood.ipa` 1.0.19 (22) — `9e0a4fd3…75abe`

**Ship the backend first.** The app calls `GET /v1/giveaways/requested`; released
against the current backend it would show "My requests couldn't load" — the exact
symptom being fixed.

Both artifacts are flagged **PRE-DEVICE-VALIDATION — NOT RELEASE APPROVED** by
`scripts/verify_local_cutout_release.py`: 1 of 5 Android device runs recorded, 0
of 1 for iOS. Run the matrix in `LOCAL_FIRST_BG_OPERATIONS.md` §6, record with
`--record-device-evidence`, and re-run the verifier with no flags.

Next version after this one: **1.0.20+23**.

---

## 10. Known risks

- **Heroku ACM certificate for `api.wearthemood.com` expires 2026-10-18.** Initial
  issuance only worked with the Cloudflare record grey-clouded; the proxy is on
  now, so auto-renewal may fail silently. Check `heroku certs:auto` from mid-September.
- **Apple Vision has never run on hardware.** `LOCAL_BG_IOS_ENABLED=true` ships the
  engine; the verifier blocks the release until a device run is recorded.
- **FASHN render quality is unverified** — it needs paid renders against the
  deployed backend. §7.6 is the first real test of Issue 1's fix.
- **Two-account giveaway and notification flows are unverified end to end.**
