# HUMAN HANDOFF — new Supabase US project (blueprint §12.9)

> Non-secret sheet. **Service-role keys / DB passwords go in the dashboard/secret store,
> never here.** Filled once the `us-east-1` project exists and the cutover completes.

## New project (fill in)

| Field | Value |
|---|---|
| Project ref | `<US_REF>` |
| Region | `us-east-1` (exact) |
| Project URL | `<US_URL>` (https://<US_REF>.supabase.co) |
| Anon / publishable key | `<paste — non-secret>` |
| Runtime DSN | Supabase **Session Pooler, port 5432** (IPv4) |
| Backup DSN | direct/session (NOT the 6543 transaction pooler) |

## Flutter build

- Set the app's Supabase URL var → `<US_URL>` and anon key → the value above (variable names per the app's env config).
- **Re-login is REQUIRED** — Tokyo-signed sessions are invalid on the new project.
- Target app version: `<fill>`.

## Redirect URLs to verify on the new project

- OAuth callback + deep-link redirect allow-list (copy from Tokyo; confirm Google works).

## Status flags (filled at cutover)

| Item | Status |
|---|---|
| Old-client Tokyo freeze applied | `<yes/no + method>` |
| Storage objects migrated (120 / ~73 MB) | `<count verified>` |
| Legacy public-URL rewrite applied | `<yes/no>` |
| Tokyo retained as cold backup (do NOT delete) | `<yes>` |
| Final cutover dump encrypted + in R2 | `<key>` |

## What the human must provide BEFORE `AUTHORIZE SUPABASE CUTOVER`

1. The `us-east-1` project created; `US_REF` / `US_URL` / anon key pasted above.
2. Config mirrored (providers, redirect URLs, SMTP, templates, rate limits) — see `SUPABASE_CUTOVER_RUNBOOK.md §3`.
3. New Flutter build ready to publish.
4. Freeze method approved (`SUPABASE_CUTOVER_RUNBOOK.md §4`).
