-- ============================================================================
-- 0006 — Style challenges (CLAUDE.md §1 pillar 4, §24) — community engagement
-- A challenge is a prompt ("Style a monochrome look") users enter by linking one
-- of their OOTD posts. challenges are seeded by the team (public read, service-
-- role write, like news_items); challenge_entries are user-owned (read-public,
-- write-own, like posts). Idempotent: safe to re-run.
-- ============================================================================

create table if not exists public.challenges (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique,
  title      text not null,
  prompt     text,                        -- the brief shown to users
  cover_url  text,
  starts_at  timestamptz not null default now(),
  ends_at    timestamptz,                 -- null = open-ended
  created_at timestamptz not null default now()
);
create index if not exists challenges_active_idx on public.challenges (starts_at, ends_at);

create table if not exists public.challenge_entries (
  id           uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  post_id      uuid not null references public.posts (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (challenge_id, post_id)          -- a post enters a challenge at most once
);
create index if not exists challenge_entries_challenge_idx
  on public.challenge_entries (challenge_id, created_at desc);
create index if not exists challenge_entries_user_idx on public.challenge_entries (user_id);

alter table public.challenges        enable row level security;
alter table public.challenge_entries enable row level security;

-- challenges: public read; writes via service role only (team-seeded).
drop policy if exists challenges_select_public on public.challenges;
create policy challenges_select_public on public.challenges for select using (true);

-- challenge_entries: read-public, write-own.
drop policy if exists challenge_entries_select_public on public.challenge_entries;
create policy challenge_entries_select_public on public.challenge_entries
  for select using (true);
drop policy if exists challenge_entries_write_own on public.challenge_entries;
create policy challenge_entries_write_own on public.challenge_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
