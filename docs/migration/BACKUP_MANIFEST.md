# BACKUP MANIFEST — Phase 1

> Complete, encrypted, restore-verified backup of Wear The Mood taken 2026-07-18 (branch `migration/heroku-azure`, base main `98df3c3`).
> **No secret values here.** The GPG passphrase is held only by the owner and never appears in this repo, logs, or chat.

## Encrypted backup archive (authoritative copy in R2)

| Field | Value |
|---|---|
| Artifact | `wtm-phase1-backup-20260718.tar.gpg` (one combined AES-256 GPG archive) |
| Encryption | `gpg --symmetric --cipher-algo AES256` (owner passphrase) |
| Encrypted size | 84,004,944 bytes |
| Encrypted SHA-256 | `9b4f7b59458cdc30cde8c70d762cda379d749875e6089e7bfee6c35acf9f1e4e` |
| Plaintext tar SHA-256 (pre-encrypt) | `542e9ef83b4c13c258c6a960a304d87eb725c3bea7bd323fd275c7e063d1c456` |
| R2 destination (authoritative) | `r2://fashionos-private/migration-backups/2026-07-18/wtm-phase1-backup-20260718.tar.gpg` |
| Local encrypted copy | scratchpad `…/scratchpad/backup/wtm-phase1-backup-20260718.tar.gpg` (session-temp — owner should copy to a durable local path; R2 is authoritative) |
| Created | 2026-07-18 |
| Retention / delete-after | **Keep through 2026-09-01** (min); owner authorizes final deletion |
| Owner | uprightseo24@gmail.com |
| Round-trip verified | ✅ downloaded from R2, SHA re-matched, decrypted to identical plaintext |
| Restore-test result | ✅ **PASS** (see below) |

## Inner artifacts (inside the archive; plaintext SHA-256)

| Artifact | Source | Bytes | SHA-256 |
|---|---|---|---|
| `wtm-git-backup-20260718.bundle` | full git, all refs (tag `pre-migration-20260718` → `98df3c3`) | 6,962,057 | `245922ec1beffb3046be0b7d3dd90b9ffff4fcec601f89c9f36ce1bec7f8724b` |
| `wtm-droplet-config.tar.gz` | droplet `/root/fashionos` config (compose, all `.env*`, Caddyfile, ufw, rendered compose, image digests, docker inspect, file inventory, resource snapshot) | 200,738 | `48288d42f2f9f0150cc35c0dce6f0f4a946ea00eb30db2cdd037976dd4c4d61c` |
| `wtm-db-export.tar.gz` | Supabase logical dump: `roles.sql` + `schema.sql` + `data.sql` (session pooler; 86 COPY blocks incl. `auth.users`/`auth.identities`) | 584,145 | `09c93fb7590fad09322155b19fcdac11f2c9a98a74564e51ddf13cafa6b9c3d2` |
| `wtm-storage-backup.tar.gz` | 120 Supabase Storage objects (76,502,885 bytes) + per-object sha256 inventory + bucket config | 76,106,226 | `a1c14beaf26ab013e44200a1c4337eabce16ee0ef1865f15e0f554db215c12b5` |
| `cloudflare-integration-config.md` | redacted DNS/Caddy/webhook/R2/integration inventory | 3,171 | `bf522e33d97e67269b47c0329937a24291edb15a62543cb26f1ac63d4d01cae1` |

## Object-count / byte-size inventory (Supabase Storage)

| Bucket | Public | Objects | Bytes |
|---|---|---|---|
| wardrobe | yes | 56 | ~20 MB |
| tryon-results | no | 30 | ~34 MB |
| post-images | yes | 19 | ~16 MB |
| avatars | no | 9 | ~2 MB |
| profile-pictures | no | 6 | ~0.6 MB |
| **Total** | | **120** | **76,502,885 bytes** |

Download verification: 120/120 objects fetched (0 failures); a full per-object SHA-256 inventory (`storage-inventory.txt`) is inside `wtm-storage-backup.tar.gz`. Representative objects across original, cutout, thumbnail, avatar, post-image, and profile-picture roles are included and restore-verified via the `storage.objects` metadata count (120) matching after DB restore.

## ⛔ DigitalOcean snapshot (§10.3) — CORRECTED 2026-07-26: **IT DOES NOT EXIST**

**The snapshot `wtm-pre-migration-20260718` was never taken.** The entry below previously claimed it
was "owner-confirmed complete 2026-07-18"; the Phase 7 pre-deletion audit proved that is false. The
snapshot ID was never recorded because there was never a snapshot to record.

Evidence gathered 2026-07-26 via the DigitalOcean API (read-only):

| Endpoint | Result |
|---|---|
| `/v2/snapshots` | 0 |
| `/v2/snapshots?resource_type=droplet` | 0 |
| `/v2/droplets/577335646/snapshots` | 0 |
| `/v2/droplets/577335646/backups` | 0 (auto-backups are **disabled** on the droplet) |
| `/v2/images?private=true` | 0 |
| **`/v2/droplets/577335646/actions`** | **4 actions total, lifetime:** `create` 2026-06-13, `power_off` / `resize` / `power_on` 2026-06-22. **No `snapshot` action was ever issued.** |

**Owner decision (2026-07-26): do NOT create a replacement snapshot.** Rationale, evidenced in
`PHASE_7_PRE_DELETE_AUDIT.md` §4–§5: the encrypted R2 archive above verifies byte-exact and already
contains the DB, Storage, droplet config and a full git bundle; **zero files on the droplet are newer
than that archive**; and the Phase 7 decommission bundle captures every env file, compose/Caddy config,
docker inspect, cron definition and loose SQL dump. A disk snapshot would add only reproducible
OS/Docker layers.

**Consequence:** there is **no full-disk restore path** for droplet 577335646. Recovery is
rebuild-and-redeploy from Git + GHCR + these backups. See `ROLLBACK_RUNBOOK.md`.

## Phase 7 decommission bundle (2026-07-26)

| Field | Value |
|---|---|
| Droplet | 577335646 (`fashion-os`, `nyc3`, 159.65.248.247) |
| Plaintext tar | `wtm-decommission-config-20260726.tar` — 3,727,360 bytes, 89 files |
| Plaintext SHA-256 | `3fe3f64c831317a518b8787ab26cd9816260dd50f6192a32c8c9d1fb59412632` |
| Encryption | `gpg --symmetric --cipher-algo AES256` (same owner passphrase as the Phase 1 archive) |
| R2 destination | `r2://fashionos-private/migration-backups/2026-07-26/wtm-decommission-config-20260726.tar.gpg` |
| Contents | compose (+rendered), Caddyfile + cert inventory, systemd units/timers, all crontabs + ofelia labels, **all 13 `.env*` files**, `docker inspect` ×5 + images/volumes/networks, host/package/port/firewall inventory, static site + legal sources, 2 pre-`0043` SQL dumps, all historical `/root` archives, `FILELIST.txt`, `SHA256SUMS.txt` |
| Retention | keep through **2026-09-01** minimum, alongside the Phase 1 archive |

## Exact restore commands

```bash
# 1. Download authoritative copy from R2
rclone copy R2:fashionos-private/migration-backups/2026-07-18/wtm-phase1-backup-20260718.tar.gpg ./
# 2. Verify integrity
sha256sum wtm-phase1-backup-20260718.tar.gpg      # expect 9b4f7b59...
# 3. Decrypt (owner passphrase; interactive)
gpg --output wtm-phase1-backup-20260718.tar --decrypt wtm-phase1-backup-20260718.tar.gpg
# 4. Unpack
tar -xf wtm-phase1-backup-20260718.tar
tar -xzf wtm-db-export.tar.gz         # -> roles.sql schema.sql data.sql
tar -xzf wtm-storage-backup.tar.gz    # -> objects/  storage-inventory.txt  storage-buckets.txt
tar -xzf wtm-droplet-config.tar.gz    # -> docker-compose.yml .env* Caddyfile ...
git clone wtm-git-backup-20260718.bundle wear-the-mood   # code + all refs
# 5. DB restore INTO A SUPABASE-INITIALISED TARGET (auth/storage schemas must pre-exist), in order:
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=0 -f roles.sql
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=0 -f schema.sql
psql "$TARGET_DB_URL" -v ON_ERROR_STOP=0 -f data.sql
# 6. Storage restore: re-upload objects/<bucket>/<path> to the target Supabase Storage buckets (service-role).
```

## Restore-test result (§10.7) — PASS

Method: downloaded the encrypted artifact **from R2**, verified SHA, decrypted, restored `roles→schema→data` into a fresh local **Supabase** stack (`supabase start`, PG 17). **Zero restore errors.** Verified counts vs. source (all exact):

- auth.users 27, auth.identities 27, **12 password hashes migrated**
- profiles 27, credits 27, credit_transactions 53, wardrobe_items 28, tryon_jobs 25, tryon_results 17, ai_jobs 17, generated_images 13, device_tokens 55, ai_usage_log 4212, news_items 1332
- storage.objects metadata 120; public tables 59; RLS-enabled 59; policies 67; public functions 197; sequences 7
- FK integrity: 0 orphans (wardrobe_items→auth.users, credit_transactions→auth.users)

Plaintext restore artifacts and the local Supabase stack were removed after verification (removed, not cryptographically shredded — SSD).

## Residual / caveat

- **R2 lifecycle**: the object-scoped R2 token cannot read bucket lifecycle config (AccessDenied). Indirect evidence shows no rule is culling `fashionos-private` (objects ~26 days old persist; retention is app-managed in code). **Recommend** the owner confirm in the Cloudflare dashboard that no lifecycle rule targets `fashionos-private` before 2026-09-01.
