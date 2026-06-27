# ADMIN_PANEL.md — Wear The Mood Ops Console

Private admin & moderation console. Code in **`admin-web/`** (Next.js App Router,
standalone); DB foundation in **`supabase/migrations/0024`–`0030`**. Mounted under
`ADMIN_PANEL_BASE_PATH` (default `/mood-ops-console-7x9`).

---

## 1. Security model (read first)

The obscure URL path is **not** the security boundary. Real security:

- Supabase Auth login + the **`admin_users`** allowlist + per-role permission matrix.
- `requireAdmin` / `requirePermission` re-verify identity **and** role inside every
  protected render, Server Action, Route Handler (incl. the audit export) and DAL fn.
- The Supabase **service_role / secret key is server-only** (`src/lib/supabase/admin.ts`
  imports `server-only`) — verified absent from the client bundle in CI/build.
- Every admin mutation is an audited Postgres RPC: it writes `admin_audit_log` **in the
  same transaction** as the mutation. `admin_audit_log` is append-only (insert/update/
  delete/truncate revoked from app roles).
- Defense-in-depth: middleware first-pass redirect, optional `ADMIN_IP_ALLOWLIST`,
  `X-Robots-Tag: noindex`, and (recommended) Supabase MFA — see §6.

## 2. Roles & permissions

`owner` · `admin` · `moderator` · `support` · `content_manager`. The matrix lives in
`admin-web/src/lib/auth/permissions.ts` (single source of truth). Highlights: only
`owner` manages admin users / hard-deletes / deletes all seed; `support` can't ban;
`content_manager` can't view full user data or ban.

## 3. Database migrations (apply order)

Applied from a laptop (never the droplet): `cd backend && python scripts/apply_all.py [.env|.env.prod]`.

| Migration | Adds |
|---|---|
| `0024_admin_panel` | admin_users, admin_audit_log, moderation cols, reports ext, appeals/actions/strikes/notes, seed_accounts, app_config, notification_campaigns, audited RPCs |
| `0025_admin_reads_and_notes` | dashboard/users/detail read RPCs + audited add_note |
| `0026_admin_content_lists` | posts/comments list RPCs |
| `0027_admin_reports_appeals` | reports/appeals queues + status/strike/appeal RPCs |
| `0028_admin_seed_studio` | seed account/post + winddown RPCs |
| `0029_admin_billing_notifications` | credit ledger / subs list / campaign RPCs |
| `0030_admin_user_management` | owner-only admin upsert/status RPCs |

All are idempotent + additive. **Already applied to dev AND prod.**

## 4. First owner

Promote a Supabase Auth user to `owner` (run from `backend/`):

```bash
# account already exists in Supabase Auth:
python scripts/create_owner_admin.py --email you@example.com
# or create the email/password account + promote:
python scripts/create_owner_admin.py --email you@example.com --password 'A-Strong-Pass-123'
# target prod:
python scripts/create_owner_admin.py --email you@example.com --env .env.prod
```

Ops-only, idempotent, never runs on app startup, never prints secrets. Add further
admins from the console's **Settings → Admin users** (owner only) instead.

## 5. Run locally + sign in

```bash
cd admin-web
cp .env.example .env.local   # fill with the DEV project keys (copy from backend/.env)
npm install
npm run dev   # http://localhost:3000/mood-ops-console-7x9/login
```

`.env.local` needs `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and the
server-only `SUPABASE_SERVICE_ROLE_KEY`. You must be in `admin_users` (active) to pass login.

## 6. Hardening checklist

- **2FA (recommended before prod use):** enable MFA in Supabase Auth; enroll each admin
  with a TOTP app. Supabase issues an AAL2 session after MFA. (A self-serve enrollment
  screen + an AAL2 enforcement check in `requireAdmin` is the next hardening step — the
  login is already MFA-compatible.)
- **IP allowlist:** set `ADMIN_IP_ALLOWLIST` (comma-separated) to restrict the whole
  console by client IP (enforced in `middleware.ts`). Empty = no restriction. Prefer
  Cloudflare Access in front for a managed gate.
- **noindex:** set on every response + in metadata. Never the security boundary.
- **Audit export** (Settings/Audit Log → Export CSV) is owner/admin only.

## 7. Deployment (DigitalOcean droplet, docker-compose)

The console is a standalone Next.js app served by Caddy under the apex domain at the
base path. **Build args** carry the public Supabase URL/anon key + base path (inlined at
build); **runtime env** (env_file) carries the server-only secret + IP allowlist.

Routing:

```text
https://wearthemood.com/mood-ops-console-7x9/*  → admin-web:3000 (Next standalone)
https://wearthemood.com/*                        → static landing + legal (unchanged)
https://api.wearthemood.com/*                    → FastAPI backend (unchanged)
```

Deploy steps (after the compose/Caddy changes are in place on the droplet):

```bash
# from the dev machine — sync admin-web/ + the updated compose/Caddyfile, then:
ssh root@<DROPLET_IP> 'cd /root/fashionos && docker compose up -d --build admin-web caddy'
curl -sI https://wearthemood.com/mood-ops-console-7x9/login   # 200 + X-Robots-Tag noindex
```

See the build args / service definition in `docker-compose.yml` (admin-web service) and
the route in `deploy/Caddyfile`. The backend §13 moderation + official-badge changes ship
with the next `docker compose up -d --build` of the `api` + `worker` services.

## 8. What the console does

Dashboard (stats + badges) · Users (search/detail + suspend/ban/shadowban/restore/soft-delete
+ notes) · Posts/Comments (hide/restore/delete) · Reports + Appeals queues · Seed/Studio
(official accounts + posts + winddown) · Credits (ledger + audited adjust) · Subscriptions ·
Notifications (in-app campaigns; device/FCM push via the backend when Firebase is live) ·
Audit Log (filter + before/after + CSV export) · Settings (config toggles + admin users +
IP allowlist + guideline map).
