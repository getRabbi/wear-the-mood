-- ============================================================================
-- 0047 — Restore Storage RLS policies on storage.objects (migration hotfix)
--
-- WHY: The Tokyo → us-east-1 Supabase cutover (Phase 3/6) restored the schema
-- via `supabase db dump`/pg_dump, which does NOT carry the RLS policies on
-- `storage.objects` (that table is owned by `supabase_storage_admin`, not by the
-- dumping `postgres` role). Result on the new US project: RLS is ENABLED on
-- storage.objects but ZERO policies exist → the default-deny denies every
-- client (authenticated) upload/read. Service-role worker writes bypass RLS and
-- kept working, which is why AI try-on results still saved while:
--   • wardrobe photo upload  → "Something went wrong"  (bug 1)
--   • save generated look    → "Couldn't save…"        (bug 2)
--
-- This migration re-creates the SAME policies originally defined in
--   0001_wardrobe_storage · 0003_avatars_storage · 0007_profile_picture ·
--   0009_tryon_results_storage · 0010_post_images_and_tags
-- consolidated here, storage-scoped only. Fully idempotent (drop-if-exists +
-- create). Safe to re-run and safe to include in any future cutover restore.
--
-- Buckets are re-asserted with `on conflict do nothing` so this is correct even
-- on a fresh project; it never changes an existing bucket's public/private flag.
-- ============================================================================

-- ---- buckets (no-op where they already exist) -----------------------------
insert into storage.buckets (id, name, public) values
  ('wardrobe',         'wardrobe',         true),
  ('avatars',          'avatars',          false),
  ('profile-pictures', 'profile-pictures', false),
  ('tryon-results',    'tryon-results',    false),
  ('post-images',      'post-images',      true)
on conflict (id) do nothing;

-- ---- wardrobe (PUBLIC read; owner-only write under {user_id}/) -------------
drop policy if exists "wardrobe_read" on storage.objects;
create policy "wardrobe_read" on storage.objects
  for select using (bucket_id = 'wardrobe');

drop policy if exists "wardrobe_insert_own" on storage.objects;
create policy "wardrobe_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "wardrobe_update_own" on storage.objects;
create policy "wardrobe_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "wardrobe_delete_own" on storage.objects;
create policy "wardrobe_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'wardrobe' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---- avatars (PRIVATE; owner-only everything) -----------------------------
drop policy if exists "avatars_select_own" on storage.objects;
create policy "avatars_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---- profile-pictures (PRIVATE; owner-only everything) --------------------
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

-- ---- tryon-results (PRIVATE; owner-only; worker writes as service-role) ----
drop policy if exists "tryon_results_select_own" on storage.objects;
create policy "tryon_results_select_own" on storage.objects
  for select to authenticated
  using (bucket_id = 'tryon-results' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "tryon_results_insert_own" on storage.objects;
create policy "tryon_results_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'tryon-results' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "tryon_results_update_own" on storage.objects;
create policy "tryon_results_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'tryon-results' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "tryon_results_delete_own" on storage.objects;
create policy "tryon_results_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'tryon-results' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---- post-images (PUBLIC read; owner-only write under {user_id}/) ----------
drop policy if exists "post_images_read" on storage.objects;
create policy "post_images_read" on storage.objects
  for select using (bucket_id = 'post-images');

drop policy if exists "post_images_insert_own" on storage.objects;
create policy "post_images_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "post_images_update_own" on storage.objects;
create policy "post_images_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "post_images_delete_own" on storage.objects;
create policy "post_images_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'post-images' and (storage.foldername(name))[1] = auth.uid()::text);
