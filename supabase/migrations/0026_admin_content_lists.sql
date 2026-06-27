-- ============================================================================
-- 0026 — Admin console content lists (posts / comments)
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §12.5–§12.6; Phase 4)
--
-- Read RPCs (SECURITY DEFINER, service_role-only) backing the console's Posts and
-- Comments moderation screens. The MUTATIONS (hide/restore/delete) already exist
-- as audited RPCs in 0024 (admin_hide_post / admin_delete_post / ... ). Idempotent,
-- additive, re-runnable. Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── posts list — search / filter (status, seed, featured) / paginate ────────
create or replace function public.admin_list_posts(
  p_search   text default null,
  p_status   text default null,
  p_seed     boolean default null,
  p_featured boolean default null,
  p_limit    int default 25,
  p_offset   int default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_limit  int := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  with base as (
    select p.id, p.user_id, p.caption, p.image_url, p.status, p.visibility,
           p.is_seed, p.is_official, p.featured_at,
           p.pinned_until, p.moderation_reason, p.like_count, p.comment_count,
           p.created_at,
           pr.display_name as author_name, pr.username as author_username,
           u.email as author_email
      from public.posts p
      join public.profiles pr on pr.id = p.user_id
      join auth.users u on u.id = p.user_id
     where (p_status is null or p.status = p_status)
       and (p_seed is null or p.is_seed = p_seed)
       and (p_featured is null
            or (p_featured and p.featured_at is not null)
            or (not p_featured and p.featured_at is null))
       and (p_search is null or p_search = ''
            or p.caption ilike '%' || p_search || '%'
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or p.id::text = p_search
            or p.user_id::text = p_search)
  ),
  page as (
    select b.*,
           (select count(*) from public.reports re
             where re.subject_type = 'post' and re.subject_id = b.id) as report_count
      from base b
     order by b.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'limit', v_limit,
    'offset', v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── comments list — search / filter (status) / paginate ─────────────────────
create or replace function public.admin_list_comments(
  p_search text default null,
  p_status text default null,
  p_limit  int default 25,
  p_offset int default 0
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_limit  int := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
begin
  with base as (
    select c.id, c.post_id, c.user_id, c.body, c.status, c.moderation_reason, c.created_at,
           pr.display_name as author_name, pr.username as author_username, u.email as author_email
      from public.comments c
      join public.profiles pr on pr.id = c.user_id
      join auth.users u on u.id = c.user_id
     where (p_status is null or c.status = p_status)
       and (p_search is null or p_search = ''
            or c.body ilike '%' || p_search || '%'
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or c.id::text = p_search)
  ),
  page as (
    select b.*,
           (select count(*) from public.reports re
             where re.subject_type = 'comment' and re.subject_id = b.id) as report_count
      from base b
     order by b.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'limit', v_limit,
    'offset', v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_list_posts(text,text,boolean,boolean,integer,integer)',
    'admin_list_comments(text,text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0026
-- ============================================================================
