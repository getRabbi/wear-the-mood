-- ============================================================================
-- 0001 — Wardrobe image storage (CLAUDE.md §8)
-- A public bucket for wardrobe (clothing) images, served via CDN. Writes are
-- RLS-restricted to each user's own {user_id}/... folder, so the app can upload
-- straight to storage with the user's session (no big files proxied through the
-- API, §8). Sensitive face/body/try-on images will use a SEPARATE PRIVATE
-- bucket + signed read URLs when that lands (§10).
-- Idempotent: safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('wardrobe', 'wardrobe', true)
on conflict (id) do nothing;

-- Read: public (clothing images at unguessable UUID paths; served via CDN).
drop policy if exists "wardrobe_read" on storage.objects;
create policy "wardrobe_read" on storage.objects
  for select using (bucket_id = 'wardrobe');

-- Insert/update/delete: only the owner, only under their own {user_id}/ folder.
drop policy if exists "wardrobe_insert_own" on storage.objects;
create policy "wardrobe_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'wardrobe'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "wardrobe_update_own" on storage.objects;
create policy "wardrobe_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'wardrobe'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "wardrobe_delete_own" on storage.objects;
create policy "wardrobe_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'wardrobe'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
