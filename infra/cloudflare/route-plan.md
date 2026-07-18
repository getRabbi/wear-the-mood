# Cloudflare route plan (blueprint §11.14) — PLAN ONLY, NOT APPLIED

> **No production DNS is changed in Phase 2 (or before Phase 6).** The public hostname
> stays on the DigitalOcean origin until the Phase 6 cutover, which requires the exact
> phrase `AUTHORIZE DNS CUTOVER`. This file is the target record plan + rollback values.

## Current (verified Phase 0) — all Cloudflare-proxied → droplet `159.65.248.247`

| Host / path | Today | Serves |
|---|---|---|
| `api.wearthemood.com` | proxied → droplet (Caddy → api:8000) | FastAPI + RevenueCat webhook |
| `wearthemood.com`, `www` | proxied → droplet (Caddy static) | landing + `/legal/*` + `/.well-known/*` + `/invite/` |
| `wearthemood.com/mood-ops-console-7x9*` | proxied → droplet (Caddy → admin-web:3000) | admin console |
| `wearthemood.com/r/*` | proxied → droplet (Caddy → api:8000) | referral redirect (dynamic) |
| `cdn.wearthemood.com` | proxied → R2 public bucket | media CDN (unchanged) |

## Target (apply the API record only at Phase 6; the rest at Gate-0-approved steps)

| Host / path | Target | Type | When |
|---|---|---|---|
| `api.wearthemood.com` | **Heroku `wtm-api-prod`** custom domain (Heroku DNS target / ACM) | CNAME, proxied | **Phase 6 cutover** |
| `wearthemood.com/r/*` | **Heroku API** — Cloudflare configuration/Worker route forwarding `/r/*` to the API host | route rule | Phase 6 (with the API record) |
| `wearthemood.com`, `www` (all other paths) | **Cloudflare Pages** project serving `deploy/site/` | Pages custom domain | Phase 4 (build) → verify → Phase 6 |
| `/.well-known/assetlinks.json`, `/.well-known/apple-app-site-association` | **Cloudflare Pages** (from `deploy/site/.well-known/`; keep JSON content-type, no redirect) | Pages | with apex |
| `/`, `/legal/*` (privacy/terms/acceptable-use), `/invite/`, `/delete-account.html` | **Cloudflare Pages** | Pages | with apex |
| `wearthemood.com/mood-ops-console-7x9*` | **Heroku Eco `wtm-admin`** (Gate 0 decision) — route rule to the admin app | route rule | Phase 4 → Phase 6 |
| `cdn.wearthemood.com` | R2 public bucket — **unchanged** | — | — |

Cloudflare proxy (orange-cloud) + current SSL mode are preserved. Verify Heroku ACM / origin-cert compatibility in the Phase 6 preflight.

## Rollback record plan (Phase 6 §15.6)

To roll the API back to DigitalOcean after cutover, restore the single record:

- `api.wearthemood.com` → **droplet origin** (the pre-cutover value; capture the exact
  current record — proxied A/CNAME to `159.65.248.247` behind Cloudflare — in the Phase 6
  preflight export before changing it).
- Leave apex/Pages/admin routes untouched during an API-only rollback (the droplet Caddy
  still serves them until decommission), or revert their route rules if they were flipped.

## Notes

- The referral path `/r/*` MUST stay dynamic (hits the API), so it is a route rule to the
  Heroku API, not a Pages static route.
- Admin server-side service-role secrecy + `ADMIN_IP_ALLOWLIST` are preserved by moving
  admin to Heroku Eco (not exposing service-role to any client).
- Full live Cloudflare export (record JSON, page/redirect rules, R2 CORS/lifecycle) is a
  Phase 1/6 backup step gated on the Cloudflare API token.
