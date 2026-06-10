-- ============================================================================
-- 0003 — Avatar storage (CLAUDE.md §10) — PRIVATE, sensitive face/body data
-- Selfies are biometric-adjacent, so unlike the public `wardrobe` bucket this
-- one is PRIVATE: no public read. The owner reads via short-lived signed URLs
-- (RLS lets them create one); try-on/moderation fetch the image through that
-- signed URL. Writes are restricted to each user's own {user_id}/ folder.
-- Idempotent: safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', false)
on conflict (id) do nothing;

-- Owner-only access (no public select). Signed URLs the owner mints inherit this.
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
