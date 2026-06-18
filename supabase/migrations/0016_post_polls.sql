-- ============================================================================
-- 0016 — Polls under posts (FEATURES_COMMUNITY_PLUS · Poll)
--
-- A post may carry ONE poll (post_polls.post_id unique). Others vote once
-- (poll_votes PK (poll_id,user_id) — one vote per user, changeable until
-- closes_at). Results are AGGREGATE-only: the API never exposes who voted what
-- beyond the caller's own choice (§10). Seeds feature_post_polls (OFF, §16).
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

create table if not exists public.post_polls (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null unique references public.posts (id) on delete cascade,
  question    text not null,
  options     jsonb not null,            -- [{index, label}], 2–4 entries
  closes_at   timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists idx_post_polls_post on public.post_polls (post_id);

create table if not exists public.poll_votes (
  poll_id      uuid not null references public.post_polls (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  option_index int  not null,
  created_at   timestamptz not null default now(),
  primary key (poll_id, user_id)            -- one vote per user
);

create index if not exists idx_poll_votes_poll on public.poll_votes (poll_id);

alter table public.post_polls enable row level security;
alter table public.poll_votes enable row level security;

-- post_polls: public read (a poll is part of a public post); all writes go
-- through the backend (service-role), so no client insert/update policy.
drop policy if exists post_polls_select_public on public.post_polls;
create policy post_polls_select_public on public.post_polls
  for select using (true);

-- poll_votes: a user may read/write ONLY their own vote row. Aggregate counts
-- are computed server-side (service-role); clients never read others' votes (§10).
drop policy if exists poll_votes_rw_own on public.poll_votes;
create policy poll_votes_rw_own on public.poll_votes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into public.feature_flags (key, enabled, description)
values ('feature_post_polls', false, 'Community: attach a poll to a post')
on conflict (key) do nothing;
