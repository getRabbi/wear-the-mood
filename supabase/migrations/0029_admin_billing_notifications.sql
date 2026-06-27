-- ============================================================================
-- 0029 — Admin credits ledger + subscriptions + notification campaigns
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §12.10–§12.11; Phase 7)
--
-- Credit ADJUSTMENT reuses admin_adjust_credits (0024) + the credit_transactions
-- ledger + app_grant_credits (decision (c)). This migration adds the READ RPCs
-- (credit ledger, subscriptions list, campaign list) and the audited campaign
-- lifecycle (create / send / cancel). "Send" fans out IN-APP notifications to the
-- target segment now (excluding banned/deleted/archived-seed); device push (FCM)
-- stays a backend concern, wired when Firebase is live. Idempotent + additive.
-- ============================================================================

-- ── per-user credit ledger + subscription + plan ────────────────────────────
create or replace function public.admin_credit_ledger(p_user_id uuid, p_limit int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; v_limit int := least(greatest(coalesce(p_limit, 30), 1), 200);
begin
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'USER_NOT_FOUND: %', p_user_id using errcode = 'P0002';
  end if;
  select jsonb_build_object(
    'credits', coalesce((select to_jsonb(c) from (
        select balance, topup_balance, daily_free_used, balance + topup_balance as total
          from public.credits where user_id = p_user_id) c),
        jsonb_build_object('balance', 0, 'topup_balance', 0, 'daily_free_used', 0, 'total', 0)),
    'subscription', (select to_jsonb(s) from (
        select tier, status, current_period_start, current_period_end, store, product_id
          from public.user_subscriptions where user_id = p_user_id) s),
    'ledger', coalesce((select jsonb_agg(to_jsonb(t)) from (
        select id, delta, reason, balance_after, ref, created_at
          from public.credit_transactions where user_id = p_user_id
         order by created_at desc limit v_limit) t), '[]'::jsonb)
  ) into v;
  return v;
end;
$$;

-- ── subscriptions list ──────────────────────────────────────────────────────
create or replace function public.admin_list_subscriptions(
  p_tier text default null, p_status text default null, p_search text default null,
  p_limit int default 25, p_offset int default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_result jsonb; v_limit int := least(greatest(coalesce(p_limit,25),1),100);
        v_offset int := greatest(coalesce(p_offset,0),0);
begin
  with base as (
    select s.user_id, s.tier, s.status, s.current_period_start, s.current_period_end,
           s.store, s.product_id, pr.display_name, pr.username, u.email
      from public.user_subscriptions s
      join public.profiles pr on pr.id = s.user_id
      join auth.users u on u.id = s.user_id
     where (p_tier is null or s.tier = p_tier)
       and (p_status is null or s.status = p_status)
       and (p_search is null or p_search = ''
            or u.email ilike '%'||p_search||'%'
            or pr.username ilike '%'||p_search||'%'
            or pr.display_name ilike '%'||p_search||'%'
            or s.user_id::text = p_search)
  ),
  page as (select * from base order by current_period_end desc nulls last limit v_limit offset v_offset)
  select jsonb_build_object('total',(select count(*) from base),'limit',v_limit,'offset',v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)) into v_result;
  return v_result;
end;
$$;

-- ── notification campaigns: list ────────────────────────────────────────────
create or replace function public.admin_list_notification_campaigns(
  p_status text default null, p_limit int default 25, p_offset int default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_result jsonb; v_limit int := least(greatest(coalesce(p_limit,25),1),100);
        v_offset int := greatest(coalesce(p_offset,0),0);
begin
  with base as (
    select c.id, c.title, c.body, c.target_segment, c.status, c.scheduled_at, c.sent_at,
           c.metadata, c.created_at, u.email as created_by_email
      from public.notification_campaigns c
      left join auth.users u on u.id = c.created_by
     where (p_status is null or c.status = p_status)
  ),
  page as (select * from base order by created_at desc limit v_limit offset v_offset)
  select jsonb_build_object('total',(select count(*) from base),'limit',v_limit,'offset',v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)) into v_result;
  return v_result;
end;
$$;

-- ── audited: create a campaign (draft) ──────────────────────────────────────
create or replace function public.admin_create_notification_campaign(
  p_admin_id uuid, p_admin_email text, p_title text, p_body text, p_segment text
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform admin_assert_active(p_admin_id);
  if p_title is null or btrim(p_title) = '' or p_body is null or btrim(p_body) = '' then
    raise exception 'TITLE_BODY_REQUIRED' using errcode = '23514';
  end if;
  if p_segment not in ('all','free_users','premium_users','inactive_7d','inactive_30d',
                       'seed_excluded','test_users') then
    raise exception 'BAD_SEGMENT: %', p_segment using errcode = '22023';
  end if;
  insert into public.notification_campaigns (title, body, target_segment, status, created_by)
  values (p_title, p_body, p_segment, 'draft', p_admin_id) returning id into v_id;
  perform admin_log_audit(p_admin_id, p_admin_email, 'create_campaign', 'campaign', v_id::text,
            p_segment, jsonb_build_object('segment', p_segment), null, null);
  return v_id;
end;
$$;

-- ── audited: send a campaign → fan out in-app notifications to the segment ───
create or replace function public.admin_send_notification_campaign(
  p_admin_id uuid, p_admin_email text, p_campaign_id bigint
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_c record; v_n int;
begin
  perform admin_assert_active(p_admin_id);
  select * into v_c from public.notification_campaigns where id = p_campaign_id;
  if v_c is null then
    raise exception 'CAMPAIGN_NOT_FOUND: %' , p_campaign_id using errcode = 'P0002';
  end if;
  if v_c.status not in ('draft','scheduled') then
    raise exception 'CAMPAIGN_NOT_SENDABLE: %', v_c.status using errcode = '22023';
  end if;

  with targets as (
    select p.id from public.profiles p
     where p.account_status not in ('banned','deleted')
       and not exists (select 1 from public.seed_accounts sa
                        where sa.user_id = p.id and sa.status = 'archived')
       and (
         v_c.target_segment = 'all'
         or (v_c.target_segment = 'seed_excluded' and p.is_seed = false)
         or (v_c.target_segment = 'premium_users' and exists (
               select 1 from public.user_subscriptions s where s.user_id = p.id
                and s.tier in ('pro','pro_max') and s.status <> 'expired'
                and (s.current_period_end is null or s.current_period_end > now())))
         or (v_c.target_segment = 'free_users' and not exists (
               select 1 from public.user_subscriptions s where s.user_id = p.id
                and s.tier in ('pro','pro_max') and s.status <> 'expired'
                and (s.current_period_end is null or s.current_period_end > now())))
         or (v_c.target_segment = 'inactive_7d' and not exists (
               select 1 from public.posts po where po.user_id = p.id and po.created_at >= now()-interval '7 days')
             and not exists (select 1 from public.comments co where co.user_id = p.id and co.created_at >= now()-interval '7 days'))
         or (v_c.target_segment = 'inactive_30d' and not exists (
               select 1 from public.posts po where po.user_id = p.id and po.created_at >= now()-interval '30 days')
             and not exists (select 1 from public.comments co where co.user_id = p.id and co.created_at >= now()-interval '30 days'))
         or (v_c.target_segment = 'test_users' and exists (
               select 1 from public.admin_users au where au.user_id = p.id and au.status = 'active'))
       )
  ),
  ins as (
    insert into public.notifications (user_id, type, title, body, target_type)
    select id, 'system', v_c.title, v_c.body, 'system' from targets
    returning 1
  )
  select count(*) into v_n from ins;

  update public.notification_campaigns
     set status = 'sent', sent_at = now(),
         metadata = metadata || jsonb_build_object('recipients', v_n), updated_at = now()
   where id = p_campaign_id;

  return admin_log_audit(p_admin_id, p_admin_email, 'send_campaign', 'campaign', p_campaign_id::text,
           v_c.target_segment, jsonb_build_object('recipients', v_n, 'channel', 'in_app'), null, null);
end;
$$;

-- ── audited: cancel a draft/scheduled campaign ──────────────────────────────
create or replace function public.admin_cancel_campaign(
  p_admin_id uuid, p_admin_email text, p_campaign_id bigint
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_status text;
begin
  perform admin_assert_active(p_admin_id);
  select status into v_status from public.notification_campaigns where id = p_campaign_id;
  if v_status is null then
    raise exception 'CAMPAIGN_NOT_FOUND: %', p_campaign_id using errcode = 'P0002';
  end if;
  if v_status not in ('draft','scheduled') then
    raise exception 'CAMPAIGN_NOT_CANCELLABLE: %', v_status using errcode = '22023';
  end if;
  update public.notification_campaigns set status = 'cancelled', updated_at = now()
   where id = p_campaign_id;
  return admin_log_audit(p_admin_id, p_admin_email, 'cancel_campaign', 'campaign',
           p_campaign_id::text, null, null, null, null);
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_credit_ledger(uuid,integer)',
    'admin_list_subscriptions(text,text,text,integer,integer)',
    'admin_list_notification_campaigns(text,integer,integer)',
    'admin_create_notification_campaign(uuid,text,text,text,text)',
    'admin_send_notification_campaign(uuid,text,bigint)',
    'admin_cancel_campaign(uuid,text,bigint)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0029
-- ============================================================================
