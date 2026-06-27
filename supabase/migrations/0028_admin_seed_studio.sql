-- ============================================================================
-- 0028 — Seed / Studio accounts + content (official launch inspiration)
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §5, §12.9; Phase 6)
--
-- Official WTM-Studio seed accounts (NOT fake real users — flagged is_seed/
-- is_official + public_label). The auth.users row is created by the console via
-- the Supabase Auth Admin API; THESE rpcs then flag the profile, register the
-- seed_accounts row, compose seed posts, run winddown, and toggle config — each
-- audited (§7.5). Seed creation is gated by app_config.seed_accounts_enabled.
-- Idempotent, additive, re-runnable. Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── owner-only assertion (for destructive winddown) ─────────────────────────
create or replace function public.admin_assert_owner(p_admin_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admin_users
                 where user_id = p_admin_id and status = 'active' and role = 'owner') then
    raise exception 'NOT_OWNER: % is not an owner', p_admin_id using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_seed_enabled()
returns boolean language sql stable set search_path = public as $$
  select coalesce((select value = 'true'::jsonb from public.app_config
                    where key = 'seed_accounts_enabled'), false);
$$;

-- ── register a seed account (after the auth user is created by the console) ──
create or replace function public.admin_register_seed_account(
  p_admin_id uuid, p_admin_email text, p_user_id uuid,
  p_display_name text, p_username text, p_bio text,
  p_seed_type text, p_public_label text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_seed bigint;
begin
  perform admin_assert_active(p_admin_id);
  if not admin_seed_enabled() then
    raise exception 'SEED_DISABLED' using errcode = '22023';
  end if;
  update public.profiles
     set display_name = p_display_name, username = p_username, bio = p_bio,
         is_seed = true, is_official = true, public_label = p_public_label,
         created_by_admin_id = p_admin_id
   where id = p_user_id;
  insert into public.seed_accounts
    (user_id, display_name, username, seed_type, status, public_label, created_by)
  values (p_user_id, p_display_name, p_username, coalesce(p_seed_type, 'studio'),
          'active', coalesce(p_public_label, 'WTM Studio'), p_admin_id)
  returning id into v_seed;
  return admin_log_audit(p_admin_id, p_admin_email, 'create_seed_account', 'seed_account',
           p_user_id::text, 'seed account ' || p_username,
           jsonb_build_object('seed_id', v_seed, 'username', p_username), null, null);
end;
$$;

-- ── compose a seed post (authored by a seed account) ────────────────────────
create or replace function public.admin_create_seed_post(
  p_admin_id uuid, p_admin_email text, p_seed_user_id uuid,
  p_caption text, p_image_url text, p_tags text[] default '{}'
) returns text
language plpgsql security definer set search_path = public as $$
declare v_post uuid;
begin
  perform admin_assert_active(p_admin_id);
  if not admin_seed_enabled() then
    raise exception 'SEED_DISABLED' using errcode = '22023';
  end if;
  if not exists (select 1 from public.seed_accounts
                 where user_id = p_seed_user_id and status = 'active') then
    raise exception 'NOT_AN_ACTIVE_SEED_ACCOUNT: %', p_seed_user_id using errcode = '22023';
  end if;
  insert into public.posts
    (user_id, caption, image_url, tags, visibility, status, is_seed, is_official,
     created_by_admin_id)
  values (p_seed_user_id, p_caption, p_image_url, coalesce(p_tags, '{}'),
          'public', 'published', true, true, p_admin_id)
  returning id into v_post;
  perform admin_log_audit(p_admin_id, p_admin_email, 'create_seed_post', 'post',
            v_post::text, 'seed post', jsonb_build_object('seed_user', p_seed_user_id), null, null);
  return v_post::text;
end;
$$;

-- ── list seed accounts (with post counts) ───────────────────────────────────
create or replace function public.admin_list_seed_accounts(
  p_status text default null, p_limit int default 50, p_offset int default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_result jsonb;
  v_limit int := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  with base as (
    select sa.id, sa.user_id, sa.display_name, sa.username, sa.seed_type, sa.status,
           sa.public_label, sa.created_at, pr.account_status as profile_status
      from public.seed_accounts sa
      join public.profiles pr on pr.id = sa.user_id
     where (p_status is null or sa.status = p_status)
  ),
  page as (
    select b.*, (select count(*) from public.posts po
                  where po.user_id = b.user_id and po.is_seed and po.status <> 'deleted')
                  as post_count
      from base b order by b.created_at desc limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from base), 'limit', v_limit, 'offset', v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── per-account status (active / paused / archived). Archiving hides its posts;
--    restoring un-archives the posts it archived (never un-hides admin-hidden) ─
create or replace function public.admin_set_seed_account_status(
  p_admin_id uuid, p_admin_email text, p_seed_id bigint, p_status text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_uid uuid;
begin
  perform admin_assert_active(p_admin_id);
  if p_status not in ('active', 'paused', 'archived') then
    raise exception 'BAD_STATUS: %', p_status using errcode = '22023';
  end if;
  select user_id into v_uid from public.seed_accounts where id = p_seed_id;
  if v_uid is null then
    raise exception 'SEED_NOT_FOUND: %', p_seed_id using errcode = 'P0002';
  end if;
  update public.seed_accounts set status = p_status, updated_at = now() where id = p_seed_id;
  if p_status = 'archived' then
    update public.posts set status = 'archived', moderated_by = p_admin_id
     where user_id = v_uid and is_seed and status = 'published';
  elsif p_status = 'active' then
    update public.posts set status = 'published', moderated_by = p_admin_id
     where user_id = v_uid and is_seed and status = 'archived';
  end if;
  return admin_log_audit(p_admin_id, p_admin_email, 'set_seed_status', 'seed_account',
           v_uid::text, p_status, jsonb_build_object('seed_id', p_seed_id, 'status', p_status),
           null, null);
end;
$$;

-- ── winddown: pause ALL seed accounts ───────────────────────────────────────
create or replace function public.admin_pause_all_seed_accounts(
  p_admin_id uuid, p_admin_email text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform admin_assert_active(p_admin_id);
  update public.seed_accounts set status = 'paused', updated_at = now() where status = 'active';
  get diagnostics v_n = row_count;
  return admin_log_audit(p_admin_id, p_admin_email, 'pause_all_seed_accounts', 'seed', 'all',
           'pause all seed accounts', jsonb_build_object('paused', v_n), null, null);
end;
$$;

-- ── winddown: delete ALL seed accounts (OWNER-only; cascade removes content) ─
create or replace function public.admin_delete_all_seed_accounts(
  p_admin_id uuid, p_admin_email text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  perform admin_assert_owner(p_admin_id);
  select count(*) into v_n from public.seed_accounts;
  -- deleting the auth user cascades to profile → posts → seed_accounts row.
  delete from auth.users where id in (select user_id from public.seed_accounts);
  return admin_log_audit(p_admin_id, p_admin_email, 'delete_all_seed_accounts', 'seed', 'all',
           'DESTRUCTIVE: delete all seed accounts', jsonb_build_object('deleted', v_n), null, null);
end;
$$;

-- ── feature / unfeature a post ──────────────────────────────────────────────
create or replace function public.admin_feature_post(
  p_admin_id uuid, p_admin_email text, p_post_id uuid, p_featured boolean
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert_active(p_admin_id);
  update public.posts
     set featured_at = case when p_featured then now() else null end
   where id = p_post_id;
  if not found then
    raise exception 'POST_NOT_FOUND: %', p_post_id using errcode = 'P0002';
  end if;
  return admin_log_audit(p_admin_id, p_admin_email,
           case when p_featured then 'feature_post' else 'unfeature_post' end,
           'post', p_post_id::text, null, jsonb_build_object('featured', p_featured), null, null);
end;
$$;

-- ── app config setter (seed flag, badges, maintenance) — audited ────────────
create or replace function public.admin_set_app_config(
  p_admin_id uuid, p_admin_email text, p_key text, p_value jsonb
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert_active(p_admin_id);
  if p_key not in ('seed_accounts_enabled', 'public_official_badges_enabled', 'maintenance_mode') then
    raise exception 'BAD_CONFIG_KEY: %', p_key using errcode = '22023';
  end if;
  insert into public.app_config (key, value, updated_by, updated_at)
  values (p_key, p_value, p_admin_id, now())
  on conflict (key) do update set value = excluded.value, updated_by = p_admin_id, updated_at = now();
  return admin_log_audit(p_admin_id, p_admin_email, 'set_app_config', 'app_config', p_key,
           null, jsonb_build_object('key', p_key, 'value', p_value), null, null);
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_assert_owner(uuid)',
    'admin_seed_enabled()',
    'admin_register_seed_account(uuid,text,uuid,text,text,text,text,text)',
    'admin_create_seed_post(uuid,text,uuid,text,text,text[])',
    'admin_list_seed_accounts(text,integer,integer)',
    'admin_set_seed_account_status(uuid,text,bigint,text)',
    'admin_pause_all_seed_accounts(uuid,text)',
    'admin_delete_all_seed_accounts(uuid,text)',
    'admin_feature_post(uuid,text,uuid,boolean)',
    'admin_set_app_config(uuid,text,text,jsonb)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0028
-- ============================================================================
