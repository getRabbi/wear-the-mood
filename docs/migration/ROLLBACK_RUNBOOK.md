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

## Placeholders (filled in later phases)

- **Phase 6** — production compute/DNS rollback: restore Cloudflare `api.wearthemood.com` record to the droplet origin; restart DO worker/Ofelia; run recovery. Exact old/new DNS values recorded at cutover.
