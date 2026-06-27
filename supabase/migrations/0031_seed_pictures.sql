-- ============================================================================
-- 0031 — Seed account profile pictures (admin console upload support)
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §12.9; founder request)
--
-- The console uploads seed images to the PUBLIC post-images bucket and stores the
-- public URL. This adds an audited RPC to set/update a seed account's picture and
-- surfaces it in the seed list. Seed POST images already flow through
-- admin_create_seed_post (no change). Idempotent + additive.
-- ============================================================================

-- ── set / update a seed account's public picture (audited) ──────────────────
create or replace function public.admin_set_seed_avatar(
  p_admin_id uuid, p_admin_email text, p_user_id uuid, p_url text
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert_active(p_admin_id);
  if not exists (select 1 from public.seed_accounts where user_id = p_user_id) then
    raise exception 'NOT_A_SEED_ACCOUNT: %', p_user_id using errcode = '22023';
  end if;
  update public.profiles
     set profile_picture_url = p_url, avatar_url = p_url
   where id = p_user_id;
  return admin_log_audit(p_admin_id, p_admin_email, 'set_seed_avatar', 'seed_account',
           p_user_id::text, null, jsonb_build_object('url', p_url), null, null);
end;
$$;

-- ── seed list — now includes the profile picture ───────────────────────────
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
           sa.public_label, sa.created_at, pr.account_status as profile_status,
           pr.profile_picture_url
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

do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_set_seed_avatar(uuid,text,uuid,text)',
    'admin_list_seed_accounts(text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0031
-- ============================================================================
