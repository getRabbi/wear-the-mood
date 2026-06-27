-- ============================================================================
-- 0025 — Admin console reads (dashboard / users) + audited note RPC
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §12.2–§12.4; Phase 3)
--
-- Read RPCs (SECURITY DEFINER, service_role-only) so the Next.js DAL stays thin
-- and all the aggregation SQL is versioned here:
--   * admin_dashboard_stats()  — the dashboard number cards
--   * admin_list_users(...)     — searchable/filterable/paginated users list
--   * admin_user_detail(uuid)   — one user's full moderation profile
-- These read across all users (joining auth.users for email), which is why they
-- run as definer + are granted ONLY to service_role; the console already gates
-- the caller via requireAdmin() before invoking them.
--
-- One audited MUTATION (§7.5 — mutation + audit in the SAME transaction):
--   * admin_add_note(...)       — attach an admin note to any moderation target
--
-- Reuses 0024 helpers (admin_assert_active / admin_log_audit). Idempotent,
-- additive, re-runnable. Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── dashboard number cards (one round-trip) ─────────────────────────────────
create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'total_users',
      (select count(*) from public.profiles),
    'new_users_today',
      (select count(*) from public.profiles where created_at >= date_trunc('day', now())),
    -- "active" = posted OR commented in the last 7 days (no last_active column).
    'active_users_7d',
      (select count(distinct uid) from (
         select user_id as uid from public.posts    where created_at >= now() - interval '7 days'
         union
         select user_id        from public.comments where created_at >= now() - interval '7 days'
       ) a),
    'total_posts',
      (select count(*) from public.posts where status <> 'deleted'),
    'posts_today',
      (select count(*) from public.posts
        where created_at >= date_trunc('day', now()) and status <> 'deleted'),
    'pending_reports',
      (select count(*) from public.reports where status in ('open', 'pending', 'reviewing')),
    'reports_today',
      (select count(*) from public.reports where created_at >= date_trunc('day', now())),
    'banned_users',
      (select count(*) from public.profiles where account_status = 'banned'),
    'suspended_users',
      (select count(*) from public.profiles where account_status = 'suspended'),
    'shadowbanned_users',
      (select count(*) from public.profiles where account_status = 'shadowbanned'),
    'active_seed_accounts',
      (select count(*) from public.seed_accounts where status = 'active'),
    'active_subscribers',
      (select count(*) from public.user_subscriptions
        where tier in ('pro', 'pro_max') and status <> 'expired'
          and (current_period_end is null or current_period_end > now())),
    'credits_issued_today',
      (select coalesce(sum(delta), 0) from public.credit_transactions
        where delta > 0 and created_at >= date_trunc('day', now())),
    'failed_tryons_today',
      (select count(*) from public.tryon_jobs
        where status = 'failed' and created_at >= date_trunc('day', now()))
  );
$$;

-- ── users list — search / filter / sort / paginate ──────────────────────────
-- Returns { total, limit, offset, rows: [...] }. Search matches email / username /
-- display_name (ILIKE) or an exact user_id. Sort: joined_desc (default) |
-- joined_asc | report_count. Tier is the EFFECTIVE tier (active sub else 'free').
create or replace function public.admin_list_users(
  p_search text default null,
  p_status text default null,
  p_seed   boolean default null,
  p_tier   text default null,
  p_sort   text default 'joined_desc',
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
    select p.id, p.display_name, p.username, p.avatar_url, p.account_status,
           p.is_seed, p.is_official, p.public_label, p.created_at, u.email,
           coalesce((
             select s.tier from public.user_subscriptions s
              where s.user_id = p.id and s.tier in ('pro', 'pro_max')
                and s.status <> 'expired'
                and (s.current_period_end is null or s.current_period_end > now())
              limit 1
           ), 'free') as tier
      from public.profiles p
      join auth.users u on u.id = p.id
     where (p_status is null or p.account_status = p_status)
       and (p_seed is null or p.is_seed = p_seed)
       and (p_search is null or p_search = ''
            or u.email ilike '%' || p_search || '%'
            or p.username ilike '%' || p_search || '%'
            or p.display_name ilike '%' || p_search || '%'
            or p.id::text = p_search)
  ),
  filtered as (
    select * from base where (p_tier is null or tier = p_tier)
  ),
  page as (
    select f.id as user_id, f.display_name, f.username, f.email, f.avatar_url,
           f.account_status, f.is_seed, f.is_official, f.public_label, f.tier,
           f.created_at,
           coalesce((select c.balance + c.topup_balance
                       from public.credits c where c.user_id = f.id), 0) as credits_total,
           (select count(*) from public.posts po
             where po.user_id = f.id and po.status <> 'deleted') as post_count,
           (select count(*) from public.reports re
             where re.reported_user_id = f.id) as report_count
      from filtered f
     order by
       case when p_sort = 'joined_asc' then f.created_at end asc nulls last,
       case when p_sort = 'report_count'
            then (select count(*) from public.reports re2 where re2.reported_user_id = f.id)
       end desc nulls last,
       f.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'limit', v_limit,
    'offset', v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── one user's full moderation profile ──────────────────────────────────────
create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'USER_NOT_FOUND: %', p_user_id using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'profile', (
      select to_jsonb(x) from (
        select p.id as user_id, p.display_name, p.username, u.email, p.avatar_url, p.bio,
               p.account_status, p.ban_reason, p.banned_at, p.banned_until, p.deleted_at,
               p.is_seed, p.is_official, p.public_label, p.timezone, p.created_at, p.moderated_by
          from public.profiles p join auth.users u on u.id = p.id
         where p.id = p_user_id
      ) x
    ),
    'subscription', (
      select to_jsonb(s) from (
        select tier, status, current_period_start, current_period_end, store, product_id
          from public.user_subscriptions where user_id = p_user_id
      ) s
    ),
    'credits', (
      select to_jsonb(c) from (
        select balance, topup_balance, daily_free_used, balance + topup_balance as total
          from public.credits where user_id = p_user_id
      ) c
    ),
    'counts', jsonb_build_object(
      'post_count',
        (select count(*) from public.posts where user_id = p_user_id and status <> 'deleted'),
      'comment_count',
        (select count(*) from public.comments where user_id = p_user_id and status <> 'deleted'),
      'follower_count', (select count(*) from public.follows where followee_id = p_user_id),
      'following_count', (select count(*) from public.follows where follower_id = p_user_id),
      'reports_against', (select count(*) from public.reports where reported_user_id = p_user_id),
      'reports_by', (select count(*) from public.reports where reporter_id = p_user_id)
    ),
    'recent_posts', coalesce((select jsonb_agg(to_jsonb(rp)) from (
       select id, caption, status, like_count, comment_count, created_at
         from public.posts where user_id = p_user_id order by created_at desc limit 10) rp), '[]'::jsonb),
    'recent_comments', coalesce((select jsonb_agg(to_jsonb(rc)) from (
       select id, post_id, body, status, created_at
         from public.comments where user_id = p_user_id order by created_at desc limit 10) rc), '[]'::jsonb),
    'reports_against_list', coalesce((select jsonb_agg(to_jsonb(ra)) from (
       select id, subject_type, subject_id, reason, status, created_at
         from public.reports where reported_user_id = p_user_id
        order by created_at desc limit 10) ra), '[]'::jsonb),
    'notes', coalesce((select jsonb_agg(to_jsonb(n)) from (
       select an.id, an.note, an.created_at, au.email as created_by_email
         from public.admin_notes an
         left join auth.users au on au.id = an.created_by
        where an.target_type = 'user' and an.target_id = p_user_id::text
        order by an.created_at desc limit 20) n), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(to_jsonb(a)) from (
       select id, action, admin_email, reason, created_at
         from public.admin_audit_log
        where target_type = 'user' and target_id = p_user_id::text
        order by created_at desc limit 20) a), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- ── audited note (mutation + audit in ONE transaction, §7.5) ────────────────
create or replace function public.admin_add_note(
  p_admin_id uuid, p_admin_email text, p_target_type text, p_target_id text, p_note text
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  perform admin_assert_active(p_admin_id);
  if p_note is null or btrim(p_note) = '' then
    raise exception 'NOTE_REQUIRED' using errcode = '23514';
  end if;
  -- target_type is validated by the admin_notes CHECK constraint.
  insert into public.admin_notes (target_type, target_id, note, created_by)
  values (p_target_type, p_target_id, p_note, p_admin_id)
  returning id into v_id;
  perform admin_log_audit(
    p_admin_id, p_admin_email, 'add_note', p_target_type, p_target_id,
    left(p_note, 200), jsonb_build_object('note_id', v_id), null, null);
  return v_id;
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_dashboard_stats()',
    'admin_list_users(text,text,boolean,text,text,integer,integer)',
    'admin_user_detail(uuid)',
    'admin_add_note(uuid,text,text,text,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0025
-- ============================================================================
