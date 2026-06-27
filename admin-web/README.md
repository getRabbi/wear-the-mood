# admin-web — Wear The Mood Ops Console

Private admin & moderation console (Next.js App Router, TypeScript, Tailwind v4).
Lives in the same repo as the app/backend; mounted under an env-configurable base
path (`ADMIN_PANEL_BASE_PATH`, default `/mood-ops-console-7x9`).

> Security model (read before changing anything): the obscure path is NOT the
> boundary. Real security = Supabase login + the `admin_users` allowlist +
> per-role permission matrix, **re-verified server-side in every protected
> render / Server Action / Route Handler** (`requireAdmin` / `requirePermission`).
> The Supabase **secret / service_role key is server-only** (`src/lib/supabase/admin.ts`
> imports `server-only`) and must never get a `NEXT_PUBLIC_` prefix.

## Setup

```bash
cd admin-web
cp .env.example .env.local   # fill REAL values (git-ignored)
npm install
npm run dev                  # http://localhost:3000/mood-ops-console-7x9
```

You must be in `admin_users` (status `active`) to get past `/login`. Seed the
first owner with the Phase-8 owner-setup script (not built yet).

## Scripts

| Command | What |
|---|---|
| `npm run dev` | Dev server (runs the Next.js version-baseline check first). |
| `npm run build` | Production build (standalone output for Docker; version-checked). |
| `npm run start` | Serve the production build. |
| `npm run lint` | ESLint (`next lint`). |
| `npm run typecheck` | `tsc --noEmit`. |

## Layout

```
src/
  app/
    layout.tsx                 root layout (noindex)
    page.tsx                   → /dashboard
    login/page.tsx             public login (+ access-denied handling)
    (protected)/
      layout.tsx               requireAdmin() gate + AppShell
      dashboard/page.tsx       Phase 2 placeholder
      {users,content,posts,…}  navigable stubs (built in later phases)
  components/                  AppShell, LoginForm, SignOutButton, ComingSoon
  lib/
    env.ts                     env access (legacy + new Supabase key fallback)
    supabase/{browser,server,admin,middleware}.ts
    auth/{require-admin,permissions}.ts
middleware.ts                  first-pass session refresh + noindex (NOT the gate)
next.config.ts                 basePath, standalone output, noindex headers
scripts/check-next-version.mjs CI guard: Next.js >= patched baseline (§4.1)
```

## Phase status

- **Phase 1 (done):** DB foundation — `supabase/migrations/0024_admin_panel.sql`.
- **Phase 2 (this):** auth shell — login, Supabase clients, `requireAdmin` +
  permission matrix, middleware, app shell, dashboard placeholder.
- Phases 3–8: dashboard data, users, moderation actions, reports/appeals, seed,
  credits/subs/notifications, hardening + deploy. See the build prompt.
