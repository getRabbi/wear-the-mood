-- ============================================================================
-- 0009 — Referral loop (CLAUDE.md §24) — viral growth
-- Each profile gets a unique referral_code (generated lazily server-side). A new
-- user redeems a code once; both sides are granted bonus credits. referee_id is
-- the PK so a user can be referred at most once. Server-verified — the client
-- never grants credits (§11, §25). Own-row read; service-role writes. Idempotent.
-- ============================================================================

alter table public.profiles add column if not exists referral_code text unique;

create table if not exists public.referrals (
  referee_id  uuid primary key references public.profiles (id) on delete cascade,
  referrer_id uuid not null references public.profiles (id) on delete cascade,
  code        text,
  created_at  timestamptz not null default now(),
  check (referee_id <> referrer_id)
);
create index if not exists referrals_referrer_idx on public.referrals (referrer_id);

alter table public.referrals enable row level security;

-- A user sees referrals where they're either side; writes go via service role.
drop policy if exists referrals_select_own on public.referrals;
create policy referrals_select_own on public.referrals
  for select using (auth.uid() = referrer_id or auth.uid() = referee_id);
