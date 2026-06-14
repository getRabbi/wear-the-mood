-- ============================================================================
-- 0007 — Profile picture (CLAUDE.md §1, §10)
-- Splits the user's *display* photo from the full-body *try-on* photo:
--   • profiles.avatar_url        -> the validated full-body try-on photo (private
--                                   `avatars` bucket, migration 0003). Unchanged.
--   • profiles.profile_picture_url -> a decorative photo the user picks freely,
--                                   stored in this new private `profile-pictures`
--                                   bucket. No pose validation; owner-only.
-- The richer body fields (gender/weight/age_range/fit/skin_tone) live inside the
-- existing `body_data` jsonb, so they need NO schema change here.
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

alter table public.profiles
  add column if not exists profile_picture_url text;

insert into storage.buckets (id, name, public)
values ('profile-pictures', 'profile-pictures', false)
on conflict (id) do nothing;

-- Owner-only access (no public select). Signed URLs the owner mints inherit this.
drop policy if exists "profile_pictures_select_own" on storage.objects;
create policy "profile_pictures_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'profile-pictures' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "profile_pictures_insert_own" on storage.objects;
create policy "profile_pictures_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'profile-pictures' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "profile_pictures_update_own" on storage.objects;
create policy "profile_pictures_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'profile-pictures' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "profile_pictures_delete_own" on storage.objects;
create policy "profile_pictures_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'profile-pictures' and (storage.foldername(name))[1] = auth.uid()::text);
