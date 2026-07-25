-- ============================================================================
-- 0048 — Restore the auth.users → profiles/credits signup trigger (migration hotfix)
--
-- WHY: Same class of gotcha as 0047. The Tokyo → us-east-1 cutover restored the
-- schema via pg_dump, which does NOT carry triggers defined on `auth.users`
-- (that table is owned by `supabase_auth_admin`, not the dumping `postgres`
-- role). Result on the new US project: the `handle_new_user()` FUNCTION restored
-- fine, but the `on_auth_user_created` TRIGGER that fires it was dropped. So:
--   • EXISTING users are unaffected (their profiles/credits rows migrated as data)
--   • Any NEW signup gets NO profiles row and NO credits row → the user's first
--     action that FK-references profiles (add wardrobe item, create post, …) 500s
--     with wardrobe_items_user_id_fkey / *_user_id_fkey violations.
--
-- This would break the Google Play closed-testing cohort (new accounts) even
-- though the founder's own existing account works. Re-create the trigger exactly
-- as defined in FASHIONOS_BASELINE.sql. Idempotent + safe to re-run.
-- ============================================================================

-- Re-assert the function so this migration is self-contained (no-op if unchanged).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  insert into public.credits (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
