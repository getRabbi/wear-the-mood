# HUMAN HANDOFF — new Supabase US project (blueprint §12.9)

> Non-secret sheet. Service-role keys / DB passwords / JWT secret are NOT here (dashboard/secret store only).
> Cutover completed **2026-07-18** — US is authoritative on the DO bridge.

## New project (LIVE)

| Field | Value |
|---|---|
| Project ref | `ghzabbceoaoertatkjyg` |
| Region | `us-east-1` |
| Project URL | `https://ghzabbceoaoertatkjyg.supabase.co` |
| Anon / publishable key (public) | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdoemFiYmNlb2FvZXJ0YXRranlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyOTg2OTAsImV4cCI6MjA5OTg3NDY5MH0.wPLZkOEba_nl8dbWDlj7XDO1fE54A_iwyDC2E0k20ZU` |
| JWT signing | HS256 (legacy shared secret — in dashboard/secret store) |
| Runtime DSN | **Session Pooler, port 5432** (`aws-0-us-east-1.pooler.supabase.com`) |
| Backup DSN | Session Pooler 5432 (direct `db.<ref>` is IPv6-only, unreachable from the bridge) |

## Flutter build

- Set the app's Supabase URL → `https://ghzabbceoaoertatkjyg.supabase.co` and anon key → the value above.
- **Re-login is REQUIRED** — Tokyo-signed sessions are invalid on the new project.
- Target app version: `<set on publish>`.

## Status (cutover complete)

| Item | Status |
|---|---|
| DB restored + verified on US | ✅ all counts match Tokyo manifest; migration 0044 applied; FK integrity 0 orphans |
| Auth migrated | ✅ 27 users, 27 identities, 12 bcrypt password hashes, 16 google identities |
| Storage objects migrated | ✅ **120 / 120** (avatars 9, post-images 19, profile-pictures 6, tryon-results 30, wardrobe 56); public + private fetch verified |
| Legacy public-URL rewrite | ✅ 143 rows (Tokyo host → US host); 0 Tokyo refs remain |
| DO bridge repointed to US | ✅ api + worker + ofelia live on US; `/v1/me` + `/v1/wardrobe` smoke = 200 |
| Old-client freeze | ⚠️ api stopped during window + JWT gate (Tokyo-signed tokens now rejected by the US-verifying API). Explicit Tokyo Storage revoke was ineffective (postgres role can't revoke on storage-admin-owned table) — residual is orphaned Tokyo Storage uploads by un-updated clients (low harm). |
| Tokyo retained as cold backup | ✅ do NOT delete |
| Final cutover dump encrypted → R2 | ⏳ pending owner GPG passphrase |

## Owner follow-ups

1. **Verify auth provider config on US:** Google OAuth client id/secret + redirect URLs must be set in the US dashboard for the 16 Google users to log in (email/password users work immediately). Confirm SMTP/templates if used.
2. **Admin console:** `admin-web` was stopped (it was on Tokyo). Rebuild it against the US URL (build arg `ADMIN_SUPABASE_URL`) + point `admin-web/.env.production` service-role at US, or leave stopped until needed.
3. **Rotate the secrets** pasted in chat (service-role, JWT secret, DB password) after launch as hygiene.
4. Distribute the new Flutter build.
