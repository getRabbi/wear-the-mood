-- ============================================================================
-- 0010 — Community: post tags + free-form post images (CLAUDE.md §1 pillar 4, §8)
-- Lets a user share ANY photo (not just an outfit cutout) and tag it. Tags live
-- on the post; images go to a PUBLIC `post-images` bucket (UGC is moderated
-- server-side before the post is created, §19). Writes restricted to the user's
-- own {user_id}/ folder. Mirrors the wardrobe bucket (0001). Idempotent.
-- ============================================================================

alter table public.posts
  add column if not exists tags text[] not null default '{}';

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

drop policy if exists "post_images_read" on storage.objects;
create policy "post_images_read" on storage.objects
  for select using (bucket_id = 'post-images');

drop policy if exists "post_images_insert_own" on storage.objects;
create policy "post_images_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "post_images_update_own" on storage.objects;
create policy "post_images_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "post_images_delete_own" on storage.objects;
create policy "post_images_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
