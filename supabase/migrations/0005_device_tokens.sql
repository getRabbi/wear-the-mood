-- ============================================================================
-- 0005 — Device push tokens (CLAUDE.md §20) — daily stylist push
-- Stores each device's FCM registration token so the timezone-aware morning
-- cron can deliver "what do I wear today?" to the user's phone. One row per
-- (user, token); a user may have several devices. push_opt_in lets a device
-- silently drop out without losing the row. Own-row RLS as defense-in-depth;
-- the cron reads them as service-role. Idempotent: safe to re-run.
-- ============================================================================

create table if not exists public.device_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  token       text not null,
  platform    text,                       -- android | ios | web
  push_opt_in boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, token)
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Own-row only: a user reads and manages just their own device tokens.
drop policy if exists device_tokens_select_own on public.device_tokens;
create policy device_tokens_select_own on public.device_tokens
  for select using (auth.uid() = user_id);

drop policy if exists device_tokens_write_own on public.device_tokens;
create policy device_tokens_write_own on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
