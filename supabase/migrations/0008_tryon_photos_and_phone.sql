-- ============================================================================
-- 0008 — Multiple try-on photos + profile phone (CLAUDE.md §1, §10)
--
-- 1) tryon_photos: a user keeps SEVERAL full-body try-on photos (a gallery) and
--    picks which one is active. Each row stores its private storage path (in the
--    `avatars` bucket at <uid>/tryon/<uuid>.jpg, RLS from 0003) + an on-device
--    quality_score (0-100). The *selected* photo's path is mirrored onto
--    profiles.avatar_url, so try-on keeps reading a single path unchanged.
-- 2) profiles.phone: optional contact phone for the personal-details screen (§3).
--
-- Own-row RLS as defense-in-depth (the worker/try-on read as service-role).
-- Idempotent: safe to re-run.
-- ============================================================================

alter table public.profiles
  add column if not exists phone text;

create table if not exists public.tryon_photos (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  storage_path  text not null,
  quality_score int,
  created_at    timestamptz not null default now()
);
create index if not exists tryon_photos_user_idx on public.tryon_photos (user_id);

alter table public.tryon_photos enable row level security;

-- Own-row only: a user reads and manages just their own try-on photos.
drop policy if exists tryon_photos_select_own on public.tryon_photos;
create policy tryon_photos_select_own on public.tryon_photos
  for select using (auth.uid() = user_id);

drop policy if exists tryon_photos_write_own on public.tryon_photos;
create policy tryon_photos_write_own on public.tryon_photos
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
