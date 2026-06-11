-- ============================================================================
-- 0004 — User blocks (CLAUDE.md §19) — UGC safety
-- A blocker hides a blocked user from their feed and prevents interaction. Unlike
-- the public `follows` table, blocks are PRIVATE: only the blocker can read their
-- own rows. The backend (service-role) filters the feed both ways so neither user
-- sees the other. Idempotent: safe to re-run.
-- ============================================================================

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists blocks_blocker_idx on public.blocks (blocker_id);
create index if not exists blocks_blocked_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;

-- Private: a user only ever sees and manages their own blocks.
drop policy if exists blocks_select_own on public.blocks;
create policy blocks_select_own on public.blocks
  for select using (auth.uid() = blocker_id);

drop policy if exists blocks_write_own on public.blocks;
create policy blocks_write_own on public.blocks
  for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);
