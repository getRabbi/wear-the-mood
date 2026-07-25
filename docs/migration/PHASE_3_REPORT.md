# PHASE 3 REPORT — Supabase Tokyo → us-east-1 migration

**Objective:** move the authoritative database + Auth (and Storage) to the new `us-east-1` project while DigitalOcean remains the compute bridge. Executed the production maintenance window under `AUTHORIZE SUPABASE CUTOVER`.

**Starting commit:** `75a868b` (Phase 3 prep) · **Ending commit:** this commit.
**Result:** ✅ **US is authoritative on the DO bridge.** Cutover verified end-to-end.

## What was done

**Prep (pre-authorization):** local rehearsal of the exact path (clean → roles → schema → data → 0044) — **zero errors**, all counts matched. Wrote `SUPABASE_CUTOVER_RUNBOOK.md`.

**Pre-freeze (US = `ghzabbceoaoertatkjyg`, us-east-1):** verified reachable + empty (PG 17.6, 0 tables/users/buckets), pre-enabled `vector`. Captured Tokyo (`jqnypzlxredupgsqxbme`) DSN + service-role.

**Maintenance window:**
1. Froze writes — stopped DO `api` + `worker` + `ofelia`; 0 in-flight jobs.
2. Final Tokyo dump (session pooler) + counts manifest.
3. Restored `roles → schema → data → 0044` into US (schema via pooler; data + 0044 backgrounded past the tool timeout). **Zero restore errors.**
4. **Verified US == Tokyo manifest exactly:** auth.users 27 / identities 27 / 12 password hashes; profiles 27; credit_transactions 53; wardrobe 28; tryon_jobs 25; tryon_results 17; ai_jobs 17; generated_images 13; device_tokens 55; ai_usage_log 4302; news_items 1351; policies 67; functions 197; sequences 7; 0044 columns/indexes present; **FK orphans 0**.
5. **Storage migration** (clarification #1): ensured 5 buckets; copied **120/120 objects (0 fail)** Tokyo→US via the Storage API (upsert); verified 120 objects / no dups / correct per-bucket counts; public + private-signed fetch = 200.
6. **URL rewrite:** dynamically rewrote **143 rows** (wardrobe_items, tryon_jobs, outfits, media_assets) Tokyo host → US host; **0 Tokyo refs remain**.
7. **Repointed DO bridge** — backend/.env → US URL/keys/JWT secret, `CONNECTION_STRING` = **Session Pooler 5432** (old env backed up); recreated `api`; started `worker` + `ofelia`.
8. **Smoke = PASS:** `/v1/health` ok; minted-JWT `/v1/me` → 200; `/v1/wardrobe` → 200 with the item's media host = `ghzabbceoaoertatkjyg` (US). Worker started clean; 0 queued jobs.

## Tests & results

Restore verification + storage verification + authenticated smoke all pass (above). Backend unit suite unchanged from Phase 2 (625/2-skip) — no code changed this phase.

## Cost-impact check

No new billable resource. US project on **Free** tier (19 MB DB + ~73 MB Storage + 27 users, comfortable). Brief API downtime during the window (closed-testing; acceptable).

## Deviations / decisions

- **Freeze via container-stop**, not the maintenance-mode middleware — the DO bridge kept the approved pre-Phase-2 code (no risky mid-cutover redeploy), and stopping `api` is a definitive write-freeze.
- **Reordered:** final-dump encryption/upload deferred to a post-window backup step (the dump is untouched by the restore; Tokyo itself is the retained final state) to minimize downtime.
- **Tokyo Storage revoke was ineffective** (the `postgres` role can't revoke on the `supabase_storage_admin`-owned `storage.objects`). Freeze relies on api-stop + the JWT gate + closed-testing coordination. Residual: an un-updated client could upload directly to Tokyo Storage (orphaned, low-harm).
- **`admin-web` stopped** (it was on Tokyo) — needs a rebuild against US (owner follow-up).
- **Direct (`db.<ref>`) DSN is IPv6-only and unreachable** from the bridge/laptop → Session Pooler 5432 used for both runtime and backup.

## Unresolved risks / follow-ups

- **Auth provider config on US** (Google OAuth client + redirect URLs) must be set in the dashboard for the 16 Google users (email users work now). — owner.
- **Final cutover dump** (`wtm-cutover-final-20260718.tar`, SHA `d301b0e5…`) still needs the owner GPG passphrase to encrypt + upload to R2.
- **Rotate** the service-role/JWT-secret/DB-password pasted in chat, post-launch.

## Rollback boundary (§12.8) — CROSSED

US is live and accepting writes, so **Tokyo is no longer an instant rollback**; a reverse-data migration would be required to return. **Tokyo is retained as a documented cold backup — do not delete.** Before the worker/api went live on US, rollback would have been a clean env/freeze reversal (that window has passed).

## Next approval phrase

```
APPROVED PHASE 3
```
