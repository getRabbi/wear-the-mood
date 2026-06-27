-- ============================================================================
-- 0032 — Seed accounts: full profile edit + SEED-TO-SEED engagement
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §5; founder request — compliant path)
--
-- Lets the admin operate seed/studio accounts like real profiles: edit the full
-- profile, and like/comment AS a seed account. COMPLIANCE GUARDRAIL: engagement
-- RPCs HARD-REQUIRE the target post to be a SEED post (posts.is_seed=true). A seed
-- account can therefore NEVER like/comment a real user's content — preventing the
-- fake-engagement the policy forbids (§5 / Google Play UGC). Everything audited.
-- Idempotent + additive.
-- ============================================================================

-- ── full profile edit for a seed account ────────────────────────────────────
create or replace function public.admin_update_seed_profile(
  p_admin_id uuid, p_admin_email text, p_user_id uuid,
  p_display_name text, p_username text, p_bio text,
  p_public_label text, p_style_tags text[] default '{}'
) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  perform admin_assert_active(p_admin_id);
  if not exists (select 1 from public.seed_accounts where user_id = p_user_id) then
    raise exception 'NOT_A_SEED_ACCOUNT: %', p_user_id using errcode = '22023';
  end if;
  if p_display_name is null or btrim(p_display_name) = ''
     or p_username is null or btrim(p_username) = '' then
    raise exception 'NAME_REQUIRED' using errcode = '23514';
  end if;
  update public.profiles
     set display_name = p_display_name, username = p_username, bio = p_bio,
         public_label = p_public_label, style_tags = coalesce(p_style_tags, '{}')
   where id = p_user_id;
  update public.seed_accounts
     set display_name = p_display_name, username = p_username,
         public_label = coalesce(p_public_label, public_label), updated_at = now()
   where user_id = p_user_id;
  return admin_log_audit(p_admin_id, p_admin_email, 'update_seed_profile', 'seed_account',
           p_user_id::text, null, jsonb_build_object('username', p_username), null, null);
end;
$$;

-- ── guard: assert (active seed actor) + (target is a seed post) ─────────────
create or replace function public.admin_assert_seed_to_seed(p_seed_user_id uuid, p_post_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.seed_accounts
                 where user_id = p_seed_user_id and status = 'active') then
    raise exception 'NOT_AN_ACTIVE_SEED_ACCOUNT: %', p_seed_user_id using errcode = '22023';
  end if;
  -- COMPLIANCE: a seed account may only engage OTHER seed content.
  if not exists (select 1 from public.posts where id = p_post_id and is_seed = true) then
    raise exception 'TARGET_NOT_A_SEED_POST: %', p_post_id using errcode = '22023';
  end if;
end;
$$;

-- ── like / unlike a SEED post AS a seed account ─────────────────────────────
create or replace function public.admin_seed_like(
  p_admin_id uuid, p_admin_email text, p_seed_user_id uuid, p_post_id uuid, p_like boolean default true
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_changed boolean := false;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_assert_seed_to_seed(p_seed_user_id, p_post_id);
  if p_like then
    insert into public.likes (user_id, post_id) values (p_seed_user_id, p_post_id)
      on conflict do nothing;
    if found then
      update public.posts set like_count = like_count + 1 where id = p_post_id;
      v_changed := true;
    end if;
  else
    delete from public.likes where user_id = p_seed_user_id and post_id = p_post_id;
    if found then
      update public.posts set like_count = greatest(like_count - 1, 0) where id = p_post_id;
      v_changed := true;
    end if;
  end if;
  return admin_log_audit(p_admin_id, p_admin_email,
           case when p_like then 'seed_like' else 'seed_unlike' end, 'post', p_post_id::text,
           null, jsonb_build_object('seed_user', p_seed_user_id, 'changed', v_changed), null, null);
end;
$$;

-- ── comment on a SEED post AS a seed account ────────────────────────────────
create or replace function public.admin_seed_comment(
  p_admin_id uuid, p_admin_email text, p_seed_user_id uuid, p_post_id uuid, p_body text
) returns text
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_assert_seed_to_seed(p_seed_user_id, p_post_id);
  if p_body is null or btrim(p_body) = '' then
    raise exception 'BODY_REQUIRED' using errcode = '23514';
  end if;
  insert into public.comments (post_id, user_id, body)
  values (p_post_id, p_seed_user_id, p_body) returning id into v_id;
  update public.posts set comment_count = comment_count + 1 where id = p_post_id;
  perform admin_log_audit(p_admin_id, p_admin_email, 'seed_comment', 'post', p_post_id::text,
            null, jsonb_build_object('seed_user', p_seed_user_id, 'comment_id', v_id), null, null);
  return v_id::text;
end;
$$;

-- ── seed list — now also returns bio + style_tags (for the profile editor) ──
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
           pr.profile_picture_url, pr.bio, pr.style_tags
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
    'admin_update_seed_profile(uuid,text,uuid,text,text,text,text,text[])',
    'admin_assert_seed_to_seed(uuid,uuid)',
    'admin_seed_like(uuid,text,uuid,uuid,boolean)',
    'admin_seed_comment(uuid,text,uuid,uuid,text)',
    'admin_list_seed_accounts(text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0032
-- ============================================================================
