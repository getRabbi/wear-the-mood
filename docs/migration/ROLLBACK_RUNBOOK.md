# ROLLBACK RUNBOOK

> Grows each phase. As of **Phase 1**, the only recovery path is restore-from-backup (no target infra exists yet, and DigitalOcean is untouched live production). Phases 3/6 add live env-repoint and DNS rollback sections.

## Current safety net (Phase 1)

DigitalOcean remains **live production, fully intact** — no rollback is needed for anything done so far (backups only; no production change). If catastrophic loss occurred, reconstruct from:

1. **DigitalOcean snapshot** `wtm-pre-migration-20260718` (droplet 577335646) — full-disk restore of the compute box (crash-consistent).
2. **Encrypted backup** `r2://fashionos-private/migration-backups/2026-07-18/wtm-phase1-backup-20260718.tar.gpg` (SHA `9b4f7b59…`) — DB (roles/schema/data incl. auth), 120 Storage objects, droplet config, git bundle. Restore steps + verification in `BACKUP_MANIFEST.md`.
3. **Git**: tag `pre-migration-20260718` → `98df3c3` (on origin) + the bundle inside the encrypted archive.

Restore-test on 2026-07-18 confirmed the encrypted DB backup rebuilds cleanly (all counts match, 0 errors).

## Retained rollback assets (do not delete before 2026-09-01)

- DO snapshot `wtm-pre-migration-20260718`
- R2 encrypted backup under `migration-backups/2026-07-18/`
- Supabase Tokyo project (stays live/authoritative until Phase 3 cutover; retained as cold backup after)

## Phase 3 — Supabase cutover (DONE 2026-07-18) — ROLLBACK BOUNDARY CROSSED

US (`ghzabbceoaoertatkjyg`, us-east-1) is authoritative on the DO bridge and accepting
writes. **Tokyo is no longer an instant rollback** — returning would require a reverse
data migration from US → Tokyo. **Tokyo is retained as a documented cold backup — do NOT delete.**

- To revert the *compute env* only (NOT a data rollback): the old Tokyo env is backed up on
  the droplet at `/root/fashionos/backend/.env.tokyo-bak.<ts>`; restoring it + recreating
  the containers points the bridge back at Tokyo — but any writes made on US since cutover
  would be lost. Only do this with an explicit reverse-migration plan.

## Phase 6 — production cutover + rollback (PREPARED, NOT EXECUTED)

Nothing in this section has been run. Production still serves from DigitalOcean.

### Ordering constraint that drives the whole sequence

The **DigitalOcean API cannot enqueue to the Azure queue** (no `AZURE_QUEUE_*` /
`QUEUE_PROVIDER` vars on the droplet — verified 2026-07-20), and the Azure batch workers
wake **only** from queue messages. So any wardrobe item created by the DO API is a
`cutout_status='queued'` row with no Azure signal.

Consequence: **stopping the DO worker before the API moves would strand every new
background-removal request.** Recovery is the bridge that makes the cutover safe — it now
re-signals stranded `queued` rows (fixed in this phase; see `PHASE_6_REPORT.md` and
migration `0045`). Rows written by the DO API have `cutout_last_signal_at IS NULL`, so
recovery picks them up on its next run.

Therefore recovery must be **enabled at the same moment the DO worker stops**, and never
before — while both planes are live it would put DO and Azure on the same row (the
120s-requeue vs 300s-lease overlap hazard).

### Values

| Item | Value |
|---|---|
| Domain | `api.wearthemood.com` |
| Current resolution | Cloudflare-proxied → `104.21.28.58` / `172.67.170.99` → droplet origin `159.65.248.247` |
| New target | `CNAME synthetic-castle-h9xyrshjsxcexe5nwsld570w.herokudns.com` |
| Rollback target | droplet origin `159.65.248.247` (Caddy terminates TLS) |
| Heroku app / release | `wtm-api-prod` v4, Basic ×1 |
| Image digest | `sha256:e5d857da6fdcfa1232cbdb405b5a2583b5288de203ddb302c5497999583d002e` |

> ⚠ **Export the exact Cloudflare record before changing it** — record type, name, content,
> TTL and proxy status — and paste it here. That needs a Zone·Read token (see blockers).

### Cutover — run in this order

```bash
# 1. Announce maintenance if the window will be visible (optional; §15.3 step 1).
heroku config:set MAINTENANCE_MODE=true -a wtm-api-prod   # only if needed

# 2. Stop the DO worker + cron. The DO API keeps running — it is the rollback path.
ssh root@159.65.248.247 'cd /root/fashionos && docker compose stop worker ofelia'
ssh root@159.65.248.247 'cd /root/fashionos && docker compose ps'   # api + caddy only

# 3. Verify no job was abandoned mid-flight (§15.3 step 4).
#    Any 'processing' row is picked up by recovery below; confirm the count is small.

# 4. Enable the Azure recovery Job — this is the bridge for queued rows.
az containerapp job update -g wtm-prod -n wtm-prod-recovery \
  --cron-expression "*/5 * * * *"

# 5. Enable the Azure cron Jobs (they replace ofelia). UTC table in PHASE_4_REPORT.md.
#    Do NOT enable these while ofelia is running — that double-fires daily-push.
az containerapp job update -g wtm-prod -n wtm-prod-cron-news         --cron-expression "<from table>"
az containerapp job update -g wtm-prod -n wtm-prod-cron-daily-push   --cron-expression "<from table>"
az containerapp job update -g wtm-prod -n wtm-prod-cron-backup       --cron-expression "<from table>"
az containerapp job update -g wtm-prod -n wtm-prod-cron-credit-reset --cron-expression "<from table>"
az containerapp job update -g wtm-prod -n wtm-prod-cron-spend-alert  --cron-expression "<from table>"
az containerapp job update -g wtm-prod -n wtm-prod-cron-giveaway-chats --cron-expression "<from table>"

# 6. Run recovery once immediately and confirm it drains the backlog.
az containerapp job start -g wtm-prod -n wtm-prod-recovery
az containerapp job execution list -g wtm-prod -n wtm-prod-recovery -o table

# 7. Flip DNS (requires AUTHORIZE DNS CUTOVER + a Zone·DNS·Edit token).
#    Change ONLY the api.wearthemood.com record. Do not touch apex or any other record.

# 8. Verify.
curl -sS https://api.wearthemood.com/healthz
curl -sS https://api.wearthemood.com/readyz        # expect {"db":true,...}
curl -sS https://api.wearthemood.com/v1/health     # legacy health, must stay 200

# 9. Disable maintenance if it was enabled.
heroku config:set MAINTENANCE_MODE=false -a wtm-api-prod
```

### Rollback — any §15.6 trigger

Rollback is fast because the DO API was never stopped.

```bash
# 1. Restore the Cloudflare api.wearthemood.com record to the droplet origin
#    (A -> 159.65.248.247, proxy status as exported in the Values table).

# 2. Stop the Azure worker plane so the two planes never run cutouts concurrently.
az containerapp job update -g wtm-prod -n wtm-prod-recovery --cron-expression "0 0 31 2 *"
for j in news daily-push backup credit-reset spend-alert giveaway-chats; do
  az containerapp job update -g wtm-prod -n wtm-prod-cron-$j --cron-expression "0 0 31 2 *"
done

# 3. Restart the DO worker + cron.
ssh root@159.65.248.247 'cd /root/fashionos && docker compose start worker ofelia'
ssh root@159.65.248.247 'cd /root/fashionos && docker compose ps'

# 4. The DO worker claims any 'queued' row directly (2s DB poll), so the backlog
#    drains without further action. Confirm:
curl -sS https://api.wearthemood.com/v1/health
```

**Rollback is compute-only.** The database is *not* rolled back — US Supabase stays
authoritative in both directions, so no data is lost by rolling back and no reverse
migration is needed.

### Blockers before `AUTHORIZE DNS CUTOVER`

1. **Heroku ACM is disabled** on `wtm-api-prod` — `heroku certs:auto` reports
   `disabled` and the custom domain shows no SNI endpoint, so Heroku currently cannot
   serve TLS for `api.wearthemood.com`. Enable ACM and let the cert issue *before* the
   flip, or the domain breaks the moment DNS moves. Note ACM validation and Cloudflare
   proxying interact — the record may need to be grey-clouded (DNS-only) while the cert
   issues.
2. **Cloudflare token not issued.** Needs **Zone · Read + Zone · DNS · Edit**. The
   Phase 4 Pages token is Account·Pages-only by design and must **not** be reused. The two
   earlier credentials remain burned and should be revoked.
3. **Azure cron UTC schedules** must be transcribed into step 5 from the finalized table
   before running it — the placeholders above are deliberately not executable.
4. **DO snapshot ID** still not recorded by the owner (outstanding since Phase 1).
