-- ============================================================================
-- 0009 — Try-on results storage (CLAUDE.md §8, §10)
-- The worker persists each generated try-on image into this PRIVATE bucket so the
-- user's history survives the provider's (FASHN) short output retention. Owner
-- reads via short-lived signed URLs; the worker writes as service-role.
-- Mirrors the avatars bucket (0003). Idempotent: safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('tryon-results', 'tryon-results', false)
on conflict (id) do nothing;

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
