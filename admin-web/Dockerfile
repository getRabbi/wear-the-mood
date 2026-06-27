# Wear The Mood Ops Console — production image (Next.js standalone output).
# Multi-stage: install deps → build → minimal runner. The standalone server
# bundles only what it needs (no node_modules shipped at runtime).
#
# IMPORTANT: NEXT_PUBLIC_* and the basePath are INLINED AT BUILD TIME, so they
# are passed as build ARGs. The SERVER-ONLY secrets (service_role key, FastAPI
# token, IP allowlist) are RUNTIME env (env_file at `docker compose up`) and are
# NEVER baked into the image.

# ── deps ─────────────────────────────────────────────────────────────────────
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

# ── build ────────────────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG ADMIN_PANEL_BASE_PATH=/mood-ops-console-7x9
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ENV ADMIN_PANEL_BASE_PATH=$ADMIN_PANEL_BASE_PATH \
    NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ── runner ───────────────────────────────────────────────────────────────────
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs

# Standalone server + static assets (+ public if present).
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
