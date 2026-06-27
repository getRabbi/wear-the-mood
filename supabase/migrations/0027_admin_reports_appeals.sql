-- ============================================================================
-- 0027 — Admin reports + appeals queues
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §12.7–§12.8; Phase 5)
--
-- Read RPCs (service_role-only) for the report/appeal queues, audited lifecycle
-- RPCs (mutation + audit in one txn, §7.5), and pending_appeals added to the
-- dashboard stats. Reuses the 0024 helpers + reuses the existing `reports` table
-- (extended in 0024) — its free-text status maps 'open' → the Pending tab.
-- Idempotent, additive, re-runnable. Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── dashboard stats — re-defined to add pending_appeals (supersedes 0025) ───
create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'total_users', (select count(*) from public.profiles),
    'new_users_today', (select count(*) from public.profiles where created_at >= date_trunc('day', now())),
    'active_users_7d', (select count(distinct uid) from (
         select user_id as uid from public.posts    where created_at >= now() - interval '7 days'
         union
         select user_id        from public.comments where created_at >= now() - interval '7 days') a),
    'total_posts', (select count(*) from public.posts where status <> 'deleted'),
    'posts_today', (select count(*) from public.posts where created_at >= date_trunc('day', now()) and status <> 'deleted'),
    'pending_reports', (select count(*) from public.reports where status in ('open', 'pending', 'reviewing')),
    'reports_today', (select count(*) from public.reports where created_at >= date_trunc('day', now())),
    'pending_appeals', (select count(*) from public.moderation_appeals where status in ('pending', 'reviewing')),
    'banned_users', (select count(*) from public.profiles where account_status = 'banned'),
    'suspended_users', (select count(*) from public.profiles where account_status = 'suspended'),
    'shadowbanned_users', (select count(*) from public.profiles where account_status = 'shadowbanned'),
    'active_seed_accounts', (select count(*) from public.seed_accounts where status = 'active'),
    'active_subscribers', (select count(*) from public.user_subscriptions
        where tier in ('pro', 'pro_max') and status <> 'expired'
          and (current_period_end is null or current_period_end > now())),
    'credits_issued_today', (select coalesce(sum(delta), 0) from public.credit_transactions
        where delta > 0 and created_at >= date_trunc('day', now())),
    'failed_tryons_today', (select count(*) from public.tryon_jobs
        where status = 'failed' and created_at >= date_trunc('day', now()))
  );
$$;

-- ── reports queue (with reporter, reported user, and a target preview) ──────
create or replace function public.admin_list_reports(
  p_status      text default null,
  p_target_type text default null,
  p_limit       int default 25,
  p_offset      int default 0
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
    select r.* from public.reports r
     where (p_status is null
            or (p_status = 'pending' and r.status in ('open', 'pending'))
            or r.status = p_status)
       and (p_target_type is null or r.subject_type = p_target_type)
  ),
  page as (
    select jsonb_build_object(
      'id', r.id,
      'subject_type', r.subject_type,
      'subject_id', r.subject_id,
      'reason', r.reason,
      'details', r.details,
      'status', r.status,
      'created_at', r.created_at,
      'reviewed_at', r.reviewed_at,
      'admin_note', r.admin_note,
      'reporter', (
        select jsonb_build_object('id', pr.id,
                 'name', coalesce(pr.display_name, pr.username), 'email', u.email)
          from public.profiles pr join auth.users u on u.id = pr.id
         where pr.id = r.reporter_id),
      'reported_user', (
        select jsonb_build_object('id', x.id,
                 'name', coalesce(p2.display_name, p2.username),
                 'email', u2.email, 'account_status', p2.account_status)
          from (select coalesce(r.reported_user_id, case r.subject_type
                  when 'post' then (select user_id from public.posts where id = r.subject_id)
                  when 'comment' then (select user_id from public.comments where id = r.subject_id)
                  when 'user' then r.subject_id end) as id) x
          left join public.profiles p2 on p2.id = x.id
          left join auth.users u2 on u2.id = x.id
         where x.id is not null),
      'target_preview', case r.subject_type
          when 'post' then (select jsonb_build_object('caption', caption, 'image_url', image_url,
                 'status', status, 'user_id', user_id) from public.posts where id = r.subject_id)
          when 'comment' then (select jsonb_build_object('body', body, 'status', status,
                 'user_id', user_id) from public.comments where id = r.subject_id)
          when 'user' then (select jsonb_build_object('display_name', display_name,
                 'username', username, 'account_status', account_status)
                 from public.profiles where id = r.subject_id)
          else null end
    ) as j, r.created_at
      from base r
     order by r.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'limit', v_limit, 'offset', v_offset,
    'rows', coalesce((select jsonb_agg(j order by created_at desc) from page), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── appeals queue ───────────────────────────────────────────────────────────
create or replace function public.admin_list_appeals(
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
    select a.* from public.moderation_appeals a
     where (p_status is null or a.status = p_status)
  ),
  page as (
    select jsonb_build_object(
      'id', a.id,
      'user', (select jsonb_build_object('id', pr.id,
                 'name', coalesce(pr.display_name, pr.username), 'email', u.email,
                 'account_status', pr.account_status)
                 from public.profiles pr join auth.users u on u.id = pr.id where pr.id = a.user_id),
      'target_type', a.target_type,
      'target_id', a.target_id,
      'action_log_id', a.action_log_id,
      'message', a.message,
      'status', a.status,
      'admin_note', a.admin_note,
      'reviewed_at', a.reviewed_at,
      'created_at', a.created_at
    ) as j, a.created_at
      from base a
     order by a.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from base),
    'limit', v_limit, 'offset', v_offset,
    'rows', coalesce((select jsonb_agg(j order by created_at desc) from page), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── audited: set a report's status (reviewing / actioned / dismissed / pending)
create or replace function public.admin_set_report_status(
  p_admin_id uuid, p_admin_email text, p_report_id uuid, p_status text, p_note text default null
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  if p_status not in ('pending', 'reviewing', 'actioned', 'dismissed') then
    raise exception 'BAD_STATUS: %', p_status using errcode = '22023';
  end if;
  select to_jsonb(s) into v_before
    from (select status, reviewed_by, admin_note from public.reports where id = p_report_id) s;
  if v_before is null then
    raise exception 'REPORT_NOT_FOUND: %', p_report_id using errcode = 'P0002';
  end if;
  update public.reports
     set status = p_status, reviewed_by = p_admin_id, reviewed_at = now(),
         admin_note = coalesce(p_note, admin_note), updated_at = now()
   where id = p_report_id;
  select to_jsonb(s) into v_after
    from (select status, reviewed_by, admin_note from public.reports where id = p_report_id) s;
  return admin_log_audit(p_admin_id, p_admin_email, 'set_report_status', 'report',
           p_report_id::text, coalesce(p_note, p_status),
           jsonb_build_object('status', p_status), v_before, v_after);
end;
$$;

-- ── audited: add a strike to a user ─────────────────────────────────────────
create or replace function public.admin_add_strike(
  p_admin_id uuid, p_admin_email text, p_user_id uuid, p_severity text,
  p_reason text, p_report_id uuid default null
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_strike bigint;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  if p_severity not in ('low', 'medium', 'high', 'critical') then
    raise exception 'BAD_SEVERITY: %', p_severity using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'USER_NOT_FOUND: %', p_user_id using errcode = 'P0002';
  end if;
  insert into public.user_strikes (user_id, severity, reason, created_by)
  values (p_user_id, p_severity, p_reason, p_admin_id)
  returning id into v_strike;
  return admin_log_audit(p_admin_id, p_admin_email, 'add_strike', 'user', p_user_id::text,
           p_reason, jsonb_build_object('severity', p_severity, 'strike_id', v_strike,
                                        'report_id', p_report_id), null, null);
end;
$$;

-- ── audited: resolve an appeal (approve restores the target) ─────────────────
create or replace function public.admin_resolve_appeal(
  p_admin_id uuid, p_admin_email text, p_appeal_id bigint, p_decision text, p_note text default null
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_appeal record;
  v_restored text := 'none';
begin
  perform admin_assert_active(p_admin_id);
  if p_decision not in ('approved', 'denied') then
    raise exception 'BAD_DECISION: %', p_decision using errcode = '22023';
  end if;
  select * into v_appeal from public.moderation_appeals where id = p_appeal_id;
  if v_appeal is null then
    raise exception 'APPEAL_NOT_FOUND: %', p_appeal_id using errcode = 'P0002';
  end if;

  update public.moderation_appeals
     set status = p_decision, reviewed_by = p_admin_id, reviewed_at = now(),
         admin_note = coalesce(p_note, admin_note), updated_at = now()
   where id = p_appeal_id;

  -- Approving an appeal restores the appealed target.
  if p_decision = 'approved' and v_appeal.target_id is not null then
    if v_appeal.target_type = 'post' then
      update public.posts set status = 'published', hidden_at = null, deleted_at = null,
             moderated_by = p_admin_id where id = v_appeal.target_id::uuid;
      v_restored := 'post';
    elsif v_appeal.target_type = 'comment' then
      update public.comments set status = 'published', hidden_at = null, deleted_at = null,
             moderated_by = p_admin_id where id = v_appeal.target_id::uuid;
      v_restored := 'comment';
    elsif v_appeal.target_type = 'user' then
      update public.profiles set account_status = 'active', ban_reason = null, banned_at = null,
             banned_until = null, deleted_at = null, moderated_by = p_admin_id
       where id = v_appeal.target_id::uuid;
      v_restored := 'user';
    end if;
  end if;

  return admin_log_audit(p_admin_id, p_admin_email, 'resolve_appeal', 'appeal',
           p_appeal_id::text, coalesce(p_note, p_decision),
           jsonb_build_object('decision', p_decision, 'restored', v_restored), null, null);
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_dashboard_stats()',
    'admin_list_reports(text,text,integer,integer)',
    'admin_list_appeals(text,integer,integer)',
    'admin_set_report_status(uuid,text,uuid,text,text)',
    'admin_add_strike(uuid,text,uuid,text,text,uuid)',
    'admin_resolve_appeal(uuid,text,bigint,text,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0027
-- ============================================================================
