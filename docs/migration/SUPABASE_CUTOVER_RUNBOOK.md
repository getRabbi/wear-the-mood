# SUPABASE CUTOVER RUNBOOK — Tokyo → us-east-1 (blueprint §12)

> The production maintenance window. **Do not execute the §5 window until the human
> has created the US project AND replied `AUTHORIZE SUPABASE CUTOVER`.** Placeholders
> `<US_REF>`, `<US_URL>`, `<TOKYO_REF>` are filled once the US project exists.

## 1. Preflight — DONE (autonomous)

| Check | Result |
|---|---|
| Rehearsal (clean local Supabase → roles → schema → data → migration 0044) | ✅ **zero errors**; counts match Tokyo (auth 27, storage.objects 120, policies 67, 12 bcrypt password hashes, 16 google identities); FK integrity 0 orphans; 0044 columns/indexes created |
| Chosen supported path | **clean target → roles.sql → schema.sql → data.sql → only newer repo migration (0044)** |
| Phase 1 backup in R2 | ✅ present (`wtm-phase1-backup-20260718.tar.gpg`, 84,004,944 B) |
| Extensions supported on target | ✅ all standard (`vector`, `pgcrypto`, `uuid-ossp`, `supabase_vault`, `pg_stat_statements`) |
| Size fit | ✅ 19 MB DB + ~73 MB Storage + 27 users → Free tier comfortably |
| Media backup | ✅ 120 objects in the Phase 1 backup; fresh copy taken at cutover |

## 2. Human prerequisites (before the window)

1. **Create the new Supabase project** in region **`us-east-1`** (exact — not a vague US). Record `project ref`, region, `URL`, **anon/publishable key** (non-secret) into `HUMAN_HANDOFF.md`. Keep service-role/DB password only in the dashboard/secret store.
2. **Enable required extensions** on the new project if not default: `vector`, `pgcrypto`, `uuid-ossp` (Supabase enables `supabase_vault`/`pg_stat_statements` by default).
3. **Prepare the new Flutter build** pointing at `<US_URL>` + new anon key (re-login expected). Have the build/upload path ready.
4. **Approve the old-client freeze method** (§4 below).
5. Confirm the DB password / connection strings for the new project (Session Pooler 5432 runtime + a direct/session backup DSN).

## 3. Mirror project configuration (§12.4 — human enters secrets in the dashboard)

Copy from Tokyo → US (values entered by the human directly; never in repo):

- **Auth providers:** Google (in use — 16 identities) + Email/password (12 users). Apple: configure if desired (0 in use today).
- **Redirect URLs / allow-list** (deep-link + OAuth callback URLs).
- **SMTP** (if configured) + email templates.
- **Auth rate limits / CAPTCHA / security settings.**
- **Realtime:** the `supabase_realtime` publication has **0 tables** today (app polls) — no table replication to enable.
- **Database webhooks / Edge Functions:** none found in Phase 0.
- **Storage settings:** the 5 buckets are recreated by the migration (§5); confirm public/private flags after (`wardrobe`+`post-images` public; `avatars`+`profile-pictures`+`tryon-results` private).

## 4. Old-client freeze (verified, reversible)

Split-brain risk is **LOW** (Phase 0): the Flutter app has **no direct DB writes** — only Supabase Auth + Storage, with all data via the API. Freeze = two layers:

1. **Automatic JWT gate (primary):** once the DO API is repointed to `<US_URL>` and restarted (§5 step 13–14), Tokyo-signed JWTs fail verification → old clients cannot perform authoritative writes (all writes go through the API). Reversible by repointing back.
2. **Reversible Tokyo belt-and-suspenders** (apply during the window, revert on rollback) — block stray old-client Auth/Storage writes to Tokyo:
   ```sql
   -- On TOKYO (reversible). Stops new auth + makes Storage read-only for clients.
   -- Revert by re-granting / re-enabling if rolling back before US writes begin.
   revoke insert, update, delete on storage.objects from anon, authenticated;
   -- (Optionally, in the dashboard: disable new sign-ups on Tokyo Auth.)
   ```
   Record the exact grants before revoking so the revert is precise.

Because distribution is limited (Play closed testing; iOS blocked), coordinate the small tester group to install the new build.

## 5. Final migration window (execute ONLY after `AUTHORIZE SUPABASE CUTOVER`)

> Orchestrated from the laptop + the droplet. DO stays the compute bridge; only its
> Supabase env changes. Commands are parameterized — fill `<US_*>`/`<TOKYO_REF>`.

**Pre-window (authorized migration-support deploy):** deploy the approved Phase 2 code to the DO bridge so it has maintenance mode + `/healthz` (same compose/combined-worker/crons; `QUEUE_PROVIDER=stub` so the queue is inert). Verify `/v1/health` + a smoke read.
```
ssh root@159.65.248.247 'cd /root/fashionos && git … / file-sync … && docker compose up -d --build api worker'   # bridge unchanged in behavior
```

1. Confirm the human has the new Flutter `<US_URL>` + anon key handoff.
2. **Maintenance mode ON (DO):** set `MAINTENANCE_MODE=true` in `/root/fashionos/backend/.env` → `docker compose restart api`. Verify a mutating request returns 503 + `/healthz` still 200.
3. **Stop the combined worker:** `docker compose stop worker`.
4. **Stop cron scheduling:** `docker compose stop ofelia`.
5. **Drain check:** confirm no `tryon_jobs`/`ai_jobs` in `processing` and no `wardrobe_items.cutout_status='processing'`; record any and let them finish or note for post-cutover recovery.
6. **Freeze Tokyo** (§4 step 2) — record pre-state, apply the reversible revoke.
7. **Final Tokyo snapshot of truth:** record counts + sequence values + a UTC timestamp (a small `\copy`/query manifest).
8. **Fresh official dump** (session pooler / direct, NOT 6543):
   ```
   npx supabase db dump --db-url "$TOKYO_DSN" -f roles.sql --role-only
   npx supabase db dump --db-url "$TOKYO_DSN" -f schema.sql
   npx supabase db dump --db-url "$TOKYO_DSN" --data-only --use-copy -x storage.buckets_vectors -x storage.vector_indexes -f data.sql
   ```
9. **Encrypt + upload the final cutover dump BEFORE restore** → `r2://fashionos-private/migration-backups/<DATE>/cutover/` (GPG, owner passphrase). Checksum.
10. **Restore into the fresh US target** in order (against `<US_DSN>` session/direct):
    ```
    psql "$US_DSN" -v ON_ERROR_STOP=0 -f roles.sql
    psql "$US_DSN" -v ON_ERROR_STOP=0 -f schema.sql
    psql "$US_DSN" -v ON_ERROR_STOP=0 -f data.sql
    psql "$US_DSN" -v ON_ERROR_STOP=1 -f supabase/migrations/0044_job_reliability.sql
    ```
11. **Review every restore error** (expected: only benign "already exists" on platform objects — documented in the rehearsal).
12. **Verify (US):** critical counts, `auth.users`(27)/identities(27), sequences(7), functions/triggers, policies(67), extensions, `storage.objects`(120) metadata, queue/job rows, 0044 columns/indexes. Compare to the step-7 manifest.

### 5a. Storage migration (owner clarification #1 — media stays in Supabase Storage)

13. **Buckets:** the 5 buckets are restored by `data.sql` (`storage.buckets`). Confirm public/private flags in US match Tokyo; recreate any missing bucket + its RLS policy.
14. **Object bytes:** copy all current Tokyo objects → US (service-role on both). Fresh copy captures anything since Phase 1:
    ```
    # download from TOKYO (as in Phase 1) → upload to US per bucket/path via the
    # Storage REST API (service-role), OR rclone between the two Supabase S3 endpoints.
    ```
15. **Rewrite stored legacy PUBLIC-bucket URLs** (private buckets store paths + are signed at read → no rewrite):
    ```sql
    -- On US. Public buckets = wardrobe, post-images. Rewrite Tokyo → US host.
    update public.wardrobe_items
       set image_url = replace(image_url, 'https://<TOKYO_REF>.supabase.co', '<US_URL>'),
           cutout_url = replace(cutout_url, 'https://<TOKYO_REF>.supabase.co', '<US_URL>'),
           thumbnail_url = replace(thumbnail_url, 'https://<TOKYO_REF>.supabase.co', '<US_URL>')
     where image_url like 'https://<TOKYO_REF>.supabase.co%' or cutout_url like '…' or thumbnail_url like '…';
    -- repeat for post images / any other column holding a public absolute URL.
    ```
16. **Verify representative images** fetch on US: an original, a cutout, a thumbnail, a profile picture, a post image, a community image.

### 5b. Repoint + restart the DO bridge

17. **Configure DO server secrets to the new target** in `/root/fashionos/backend/.env`:
    `SUPABASE_URL=<US_URL>`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`/JWKS, `CONNECTION_STRING` = **Session Pooler 5432**, `CONNECTION_STRING_DIRECT` = direct/session backup DSN.
18. **Restart DO compose** (bridge services): `docker compose up -d api` (worker/cron stay stopped).
19. **Smoke (worker/cron still paused):** `/readyz` ready; login with a migrated user; feed; closet; upload; one local rembg; one controlled FASHN; credit deduct/refund; R2 serve; FCM registration where practical.
20. **Start bridge worker/cron** only when smoke passes: `docker compose start worker ofelia`.
21. **Disable maintenance:** `MAINTENANCE_MODE=false` → `docker compose restart api`.
22. **Human distributes the new Flutter build** (`<US_URL>` + anon key); re-login expected.

## 6. Rollback boundary (§12.8)

- **Before any new writes on US:** rollback = repoint DO env back to Tokyo + revert the §4 freeze + restart. Zero data loss.
- **After new writes begin on US:** Tokyo is **no longer an instant rollback** — a reverse-data migration would be required. Do **not** call Tokyo an instant rollback past this point.
- **Tokyo is retained as a cold backup — do NOT delete it.**

## 7. Handoff (§12.9) → `HUMAN_HANDOFF.md`

New URL, anon/publishable key, project ref, redirect URLs to verify, Flutter build variable names, explicit "re-login required" note, old-client freeze status, target app version.
