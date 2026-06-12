-- ============================================================================
-- 0008 — Subscription entitlements (CLAUDE.md §18) — monetization
-- One row per user holding their CURRENT premium entitlement, kept in sync by
-- the RevenueCat webhook (service-role write). Premium actions are gated
-- server-side against this table — the client's entitlement is never trusted
-- (§18, §25). Own-row read; writes via service role only. Idempotent.
-- ============================================================================

create table if not exists public.entitlements (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  active     boolean not null default false,
  product_id text,
  store      text,                       -- play_store | app_store | stripe | promo
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.entitlements enable row level security;

-- Own-row read; the webhook writes as service role (bypasses RLS).
drop policy if exists entitlements_select_own on public.entitlements;
create policy entitlements_select_own on public.entitlements
  for select using (auth.uid() = user_id);
