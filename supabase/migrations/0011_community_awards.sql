-- ============================================================================
-- 0011 — Community Style-Score awards (CLAUDE.md §1 pillar 4, §24)
-- Winner history for the monthly leaderboard: one row per awarded month (the
-- `unique (period_month)` makes the granting cron idempotent). Public read so the
-- app can show "past winners"; writes are service-role only (the cron).
-- Idempotent: safe to re-run.
-- ============================================================================

create table if not exists public.community_awards (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  period_month date not null,          -- first day of the awarded month
  score        integer not null default 0,
  created_at   timestamptz not null default now(),
  unique (period_month)
);
create index if not exists community_awards_month_idx
  on public.community_awards (period_month desc);

alter table public.community_awards enable row level security;

drop policy if exists community_awards_select_public on public.community_awards;
create policy community_awards_select_public on public.community_awards
  for select using (true);
-- No write policy: only the service-role cron inserts (RLS-bypassing).
