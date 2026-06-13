# Deploy the backend to a DigitalOcean droplet

One 2 GB droplet runs everything — api + worker + the two crons + Caddy (HTTPS) —
via `docker-compose.yml`. Supabase stays the managed database (already
provisioned). This is the recommended host while you have DO credit (always-on,
no cold starts, ≈free for a year). Render (`render.yaml`) remains a fallback.

## 1. Create the droplet

- DigitalOcean → Create → Droplet → **Ubuntu 24.04**, **Basic / Regular, 2 GB / 1 vCPU** (~$12/mo, covered by your credit). Add your SSH key.
- (Easiest: pick the **Docker** Marketplace image so Docker is preinstalled.)

## 2. DNS for HTTPS (recommended)

Point an A record at the droplet IP, e.g. `api.wearthemood.com → <droplet-ip>`. Caddy
will auto-issue a Let's Encrypt cert. (You can skip this and test on the IP over
HTTP first, but the mobile app needs HTTPS.)

## 3. Install Docker (skip if you used the Docker image)

```
ssh root@<droplet-ip>
apt-get update && apt-get install -y docker.io docker-compose-plugin git
```

## 4. Get the code + secrets

```
git clone <your-repo-url> fashionos && cd fashionos
```

Create **`backend/.env`** with your prod values (copy the Supabase block from your
local `backend/.env.prod`, and the AI keys from your dev `backend/.env`):

```
ENVIRONMENT=prod
SUPABASE_URL=...                 SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...    SUPABASE_JWT_SECRET=...
CONNECTION_STRING=...            # prod pooler URI
OPENAI_API_KEY=...   ANTHROPIC_API_KEY=...   FASHN_API_KEY=...
# News (turn on real RSS):
NEWS_PROVIDER=rss
NEWS_RSS_FEEDS=https://www.businessoffashion.com/arc/outboundfeeds/rss/,https://hypebeast.com/feed,https://www.highsnobiety.com/feed/,https://www.vogue.com/feed/rss,https://fashionista.com/.rss/full/
# Push (after Firebase service-account is ready):
PUSH_PROVIDER=fcm   FCM_PROJECT_ID=fashionos-3d779   FCM_CREDENTIALS_JSON={...one line...}
# Observability:
SENTRY_DSN=...   POSTHOG_API_KEY=...
```

Create a **root `.env`** (for Caddy's domain — git-ignored):

```
API_DOMAIN=api.wearthemood.com     # or `:80` to test on the IP over HTTP
```

## 5. Launch

```
docker compose up -d --build
```

First build pulls the rembg model into a volume (a few minutes). Then:

```
docker compose ps                 # api, worker, caddy, ofelia all "running"
curl https://api.wearthemood.com/v1/health   # -> {"status":"ok",...}
docker compose logs -f api        # tail logs
```

## 6. Point the app at it

Set the Flutter app's API base URL to `https://api.wearthemood.com` and rebuild.

## Operating it

- **Deploy an update:** `git pull && docker compose up -d --build`
- **Crons:** ofelia runs `news` every 6h and the daily push hourly (it only sends
  to users whose local hour == `DAILY_PUSH_HOUR`). Check: `docker compose logs ofelia`.
- **Worker memory:** rembg is the heavy bit. If the worker OOMs on 2 GB, set
  `BG_PROVIDER=stub` in `backend/.env` (skips auto-cutouts; everything else — OpenAI
  embeddings, stylist, tagging — is light) and restart, or size the droplet up.
- **Schema changes later:** apply migrations from your laptop with
  `python scripts/apply_all.py .env.prod` (don't run DDL from the droplet).
