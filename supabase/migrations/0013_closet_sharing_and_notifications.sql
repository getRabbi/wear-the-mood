-- ============================================================================
-- 0013 — Public closet sharing + in-app notifications (CLAUDE.md §1 pillar 4)
--
-- 1) profiles.show_public_closet — a master opt-in for showing the user's closet
--    on their public profile. Default FALSE: nothing is shared until the user
--    turns it on (private/safe by default; backward-compatible). The public
--    closet endpoint only returns wardrobe *items* (image/name/category/colour) —
--    never cost, body/try-on photos, email, phone or any private profile data.
--
-- 2) notifications — the in-app activity feed (likes/comments/follows/system…).
--    Own-row read + update (mark read); inserts are service-role only (the
--    backend creates them), so a client can never forge a notification.
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- 1) Public closet opt-in -----------------------------------------------------
alter table public.profiles
  add column if not exists show_public_closet boolean not null default false;

-- 2) Notifications ------------------------------------------------------------
create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  actor_id    uuid references public.profiles (id) on delete set null,
  type        text not null,            -- like|comment|follow|try_on_ready|…
  title       text not null,
  body        text,
  target_type text,                     -- post|user|tryon|credits|…
  target_id   text,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (user_id) where is_read = false;

alter table public.notifications enable row level security;

-- A user only ever sees + marks-read their OWN notifications.
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select using (auth.uid() = user_id);

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
-- No insert policy: only the service-role backend inserts (RLS-bypassing), so
-- notifications can't be forged by clients.
