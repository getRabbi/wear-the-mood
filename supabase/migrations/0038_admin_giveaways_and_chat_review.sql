-- ============================================================================
-- 0038 — Admin moderation for giveaways + pickup-chat report review
-- (ADMIN_GAP_REPORT.md Phase D1 — findings 2.1, 2.2, 2.3, 3.1, 3.3, 6.2)
--
-- The app grew two UGC surfaces the console can't moderate:
--   * giveaways — public listings with images and P2P meetups, but NO moderation
--     columns (0020's status is lifecycle-only), so there is no hide/soft-delete;
--   * giveaway pickup chats — a report freezes the transcript (0037 report_flag)
--     so the retention cron never redacts it, but NOTHING could clear the flag,
--     leaving reported meetup messages retained forever (§10) with no reviewer.
--
-- This migration adds:
--   1. giveaways moderation columns (hidden_at / deleted_at / moderated_by /
--      moderation_reason / is_seed) + defense-in-depth RLS/grants;
--   2. pickup-chat report_cleared_by/at;
--   3. admin_list_reports v2 — resolves subject_type 'giveaway' and
--      'giveaway_chat' (previously rendered with NULL target/reported-user);
--   4. audited RPCs: list/detail giveaways, hide/restore/close/delete giveaway,
--      view pickup-chat transcript (view itself is audited — reading private
--      messages must leave a trace), review pickup-chat report (clear flag →
--      the cron redacts on its normal schedule, or keep frozen + escalate);
--   5. the report-queue index (status, created_at).
--
-- Idempotent, additive, re-runnable. Apply to DEV first, verify, then prod.
-- Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── 1. giveaways — standard moderation column set (mirrors posts, 0024) ─────
alter table public.giveaways
  add column if not exists hidden_at         timestamptz,
  add column if not exists deleted_at        timestamptz,
  add column if not exists moderated_by      uuid references auth.users (id),
  add column if not exists moderation_reason text,
  add column if not exists is_seed           boolean not null default false;

-- Public browse scan (backend filters live rows).
create index if not exists giveaways_live_idx
  on public.giveaways (status, created_at desc)
  where hidden_at is null and deleted_at is null;

-- Report queue scan (finding 6.2 — 0024 indexed subject only).
create index if not exists idx_reports_status_created
  on public.reports (status, created_at desc);

-- Defense-in-depth: a hidden/deleted listing disappears from direct PostgREST
-- reads too (the app reads via the backend, which filters — this is the §11
-- second layer). The owner still sees their own listing.
drop policy if exists giveaways_select_public on public.giveaways;
create policy giveaways_select_public on public.giveaways
  for select using (
    deleted_at is null and (hidden_at is null or auth.uid() = owner_id)
  );

-- The baseline write-own policy is FOR ALL, so an owner could UPDATE their own
-- moderation columns straight through PostgREST (e.g. clear hidden_at). RLS has
-- no column granularity — use column-level grants instead: revoke blanket
-- UPDATE, re-grant only the listing fields. The backend writes as service_role
-- (table owner) and is unaffected.
do $$
begin
  revoke update on public.giveaways from authenticated, anon;
  grant update (wardrobe_item_id, title, description, images, size, category,
                condition, area_label, status, updated_at)
    on public.giveaways to authenticated;
exception when undefined_object then null;  -- roles absent on non-Supabase DBs
end $$;

-- ── 2. pickup chats — record who cleared a report flag, and when (3.3) ──────
alter table public.giveaway_pickup_chats
  add column if not exists report_cleared_by uuid references auth.users (id),
  add column if not exists report_cleared_at timestamptz;

-- ── 3. admin_list_reports v2 — resolve the two new subject types ────────────
-- Same signature as 0027 (CREATE OR REPLACE keeps the service_role grant).
--   * 'giveaway'       → reported_user = the listing owner; preview = listing.
--   * 'giveaway_chat'  → reported_user stays NULL (either participant may be
--     the offender); preview carries both participants + chat state so the
--     console can route to the transcript review.
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
                  when 'giveaway' then (select owner_id from public.giveaways where id = r.subject_id)
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
          when 'giveaway' then (select jsonb_build_object('title', g.title,
                 'image_url', g.images->>0, 'status', g.status,
                 'hidden_at', g.hidden_at, 'deleted_at', g.deleted_at,
                 'user_id', g.owner_id)
                 from public.giveaways g where g.id = r.subject_id)
          when 'giveaway_chat' then (select jsonb_build_object(
                 'chat_id', c.id, 'chat_status', c.status,
                 'report_flag', c.report_flag, 'expires_at', c.expires_at,
                 'giveaway_id', c.giveaway_id, 'giveaway_title', g.title,
                 'owner', jsonb_build_object('id', c.owner_id,
                    'name', coalesce(po.display_name, po.username)),
                 'requester', jsonb_build_object('id', c.requester_id,
                    'name', coalesce(pq.display_name, pq.username)))
                 from public.giveaway_pickup_chats c
                 join public.giveaways g on g.id = c.giveaway_id
                 join public.profiles po on po.id = c.owner_id
                 join public.profiles pq on pq.id = c.requester_id
                 where c.id = r.subject_id)
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

-- ── 4a. giveaway list / detail (read RPCs, mirrors admin_list_posts) ─────────
create or replace function public.admin_list_giveaways(
  p_search text default null,
  p_status text default null,     -- lifecycle: available|reserved|claimed|closed
  p_state  text default null,     -- moderation: live|hidden|deleted
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
    select g.id, g.owner_id, g.title, g.description, g.images->>0 as image_url,
           g.size, g.category, g.condition, g.area_label, g.status,
           g.hidden_at, g.deleted_at, g.moderation_reason, g.is_seed, g.created_at,
           case when g.deleted_at is not null then 'deleted'
                when g.hidden_at  is not null then 'hidden'
                else 'live' end as moderation_state,
           pr.display_name as owner_name, pr.username as owner_username,
           u.email as owner_email
      from public.giveaways g
      join public.profiles pr on pr.id = g.owner_id
      join auth.users u on u.id = g.owner_id
     where (p_status is null or g.status = p_status)
       and (p_state is null
            or (p_state = 'deleted' and g.deleted_at is not null)
            or (p_state = 'hidden'  and g.hidden_at is not null and g.deleted_at is null)
            or (p_state = 'live'    and g.hidden_at is null and g.deleted_at is null))
       and (p_search is null or p_search = ''
            or g.title ilike '%' || p_search || '%'
            or g.description ilike '%' || p_search || '%'
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or g.id::text = p_search
            or g.owner_id::text = p_search)
  ),
  page as (
    select b.*,
           (select count(*) from public.giveaway_claims c
             where c.giveaway_id = b.id) as claim_count,
           (select count(*) from public.reports re
             where re.subject_type = 'giveaway' and re.subject_id = b.id) as report_count
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

create or replace function public.admin_giveaway_detail(p_giveaway_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'giveaway', (
      select jsonb_build_object(
        'id', g.id, 'owner_id', g.owner_id, 'title', g.title,
        'description', g.description, 'images', g.images, 'size', g.size,
        'category', g.category, 'condition', g.condition,
        'area_label', g.area_label, 'status', g.status,
        'hidden_at', g.hidden_at, 'deleted_at', g.deleted_at,
        'moderation_reason', g.moderation_reason, 'is_seed', g.is_seed,
        'created_at', g.created_at,
        'owner_name', coalesce(pr.display_name, pr.username),
        'owner_email', u.email, 'owner_status', pr.account_status)
        from public.giveaways g
        join public.profiles pr on pr.id = g.owner_id
        join auth.users u on u.id = g.owner_id
       where g.id = p_giveaway_id),
    'claims', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'claimer_id', c.claimer_id,
        'claimer_name', coalesce(pc.display_name, pc.username),
        'message', c.message, 'status', c.status, 'created_at', c.created_at)
        order by c.created_at)
        from public.giveaway_claims c
        join public.profiles pc on pc.id = c.claimer_id
       where c.giveaway_id = p_giveaway_id), '[]'::jsonb),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pc.id, 'status', pc.status, 'report_flag', pc.report_flag,
        'requester_id', pc.requester_id,
        'requester_name', coalesce(pq.display_name, pq.username),
        'approved_at', pc.approved_at, 'expires_at', pc.expires_at)
        order by pc.created_at desc)
        from public.giveaway_pickup_chats pc
        join public.profiles pq on pq.id = pc.requester_id
       where pc.giveaway_id = p_giveaway_id), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'reason', r.reason, 'status', r.status,
        'created_at', r.created_at) order by r.created_at desc)
        from public.reports r
       where r.subject_type = 'giveaway' and r.subject_id = p_giveaway_id),
      '[]'::jsonb)
  ) into v_result;
  if v_result->'giveaway' is null or v_result->>'giveaway' is null then
    raise exception 'GIVEAWAY_NOT_FOUND: %', p_giveaway_id using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- ── 4b. audited giveaway mutations (mirror the 0024 post/user actions) ──────
create or replace function public.admin_giveaway_snapshot(p_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select to_jsonb(s) from (
    select status, hidden_at, deleted_at, moderated_by, moderation_reason
      from public.giveaways where id = p_id
  ) s;
$$;

create or replace function public.admin_hide_giveaway(
  p_admin_id uuid, p_admin_email text, p_giveaway_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_giveaway_snapshot(p_giveaway_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_giveaway_id using errcode = 'P0002';
  end if;
  update public.giveaways
     set hidden_at = coalesce(hidden_at, now()), moderated_by = p_admin_id,
         moderation_reason = p_reason, updated_at = now()
   where id = p_giveaway_id
   returning owner_id into v_owner;
  v_after := admin_giveaway_snapshot(p_giveaway_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'hide_giveaway', 'giveaway', p_giveaway_id::text,
          v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'hide_giveaway', 'giveaway',
           p_giveaway_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

create or replace function public.admin_restore_giveaway(
  p_admin_id uuid, p_admin_email text, p_giveaway_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_giveaway_snapshot(p_giveaway_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_giveaway_id using errcode = 'P0002';
  end if;
  update public.giveaways
     set hidden_at = null, deleted_at = null, moderated_by = p_admin_id,
         moderation_reason = p_reason, updated_at = now()
   where id = p_giveaway_id
   returning owner_id into v_owner;
  v_after := admin_giveaway_snapshot(p_giveaway_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'restore_giveaway', 'giveaway', p_giveaway_id::text,
          v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'restore_giveaway', 'giveaway',
           p_giveaway_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

create or replace function public.admin_close_giveaway(
  p_admin_id uuid, p_admin_email text, p_giveaway_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_giveaway_snapshot(p_giveaway_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_giveaway_id using errcode = 'P0002';
  end if;
  update public.giveaways
     set status = 'closed', moderated_by = p_admin_id,
         moderation_reason = p_reason, updated_at = now()
   where id = p_giveaway_id
   returning owner_id into v_owner;
  v_after := admin_giveaway_snapshot(p_giveaway_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'close_giveaway', 'giveaway', p_giveaway_id::text,
          v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'close_giveaway', 'giveaway',
           p_giveaway_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- Soft delete. Also cancels a live pickup chat so the retention cron redacts it
-- on its normal schedule (an admin-deleted listing must not keep an open chat).
create or replace function public.admin_delete_giveaway(
  p_admin_id uuid, p_admin_email text, p_giveaway_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_giveaway_snapshot(p_giveaway_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_giveaway_id using errcode = 'P0002';
  end if;
  update public.giveaways
     set deleted_at = coalesce(deleted_at, now()), moderated_by = p_admin_id,
         moderation_reason = p_reason, updated_at = now()
   where id = p_giveaway_id
   returning owner_id into v_owner;
  update public.giveaway_pickup_chats
     set status = 'cancelled', cancelled_at = coalesce(cancelled_at, now()),
         updated_at = now()
   where giveaway_id = p_giveaway_id and status = 'active';
  v_after := admin_giveaway_snapshot(p_giveaway_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'delete_giveaway', 'giveaway', p_giveaway_id::text,
          v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'delete_giveaway', 'giveaway',
           p_giveaway_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- ── 4c. pickup-chat transcript view + report review ─────────────────────────
-- VIEWING a private transcript is itself a privileged act (§10) — the RPC logs
-- an audit row for every read, so access always leaves a trace. Volatile on
-- purpose (it writes the audit row in the same transaction as the read).
create or replace function public.admin_get_pickup_chat_transcript(
  p_admin_id uuid, p_admin_email text, p_chat_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_result jsonb;
begin
  perform admin_assert_active(p_admin_id);
  select jsonb_build_object(
    'chat', jsonb_build_object(
      'id', c.id, 'giveaway_id', c.giveaway_id, 'status', c.status,
      'report_flag', c.report_flag, 'report_cleared_at', c.report_cleared_at,
      'pickup_plan', c.pickup_plan, 'approved_at', c.approved_at,
      'expires_at', c.expires_at, 'created_at', c.created_at,
      'giveaway_title', g.title),
    'owner', jsonb_build_object('id', c.owner_id,
      'name', coalesce(po.display_name, po.username), 'email', uo.email,
      'account_status', po.account_status),
    'requester', jsonb_build_object('id', c.requester_id,
      'name', coalesce(pq.display_name, pq.username), 'email', uq.email,
      'account_status', pq.account_status),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'sender_id', m.sender_id, 'body', m.body,
        'body_deleted', m.body_deleted, 'created_at', m.created_at)
        order by m.created_at)
        from public.giveaway_chat_messages m
       where m.chat_id = c.id), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'reason', r.reason, 'status', r.status,
        'reporter_id', r.reporter_id, 'created_at', r.created_at)
        order by r.created_at desc)
        from public.reports r
       where r.subject_type = 'giveaway_chat' and r.subject_id = c.id),
      '[]'::jsonb)
  ) into v_result
    from public.giveaway_pickup_chats c
    join public.giveaways g on g.id = c.giveaway_id
    join public.profiles po on po.id = c.owner_id
    join auth.users uo on uo.id = c.owner_id
    join public.profiles pq on pq.id = c.requester_id
    join auth.users uq on uq.id = c.requester_id
   where c.id = p_chat_id;
  if v_result is null then
    raise exception 'CHAT_NOT_FOUND: %', p_chat_id using errcode = 'P0002';
  end if;
  perform admin_log_audit(p_admin_id, p_admin_email, 'view_chat_transcript',
    'giveaway_chat', p_chat_id::text, null, '{}'::jsonb, null, null);
  return v_result;
end;
$$;

-- Review decision on a reported chat:
--   'clear'       → no violation: drop report_flag (recording who/when), so the
--                   retention cron redacts the transcript on its normal pass;
--   'keep_frozen' → violation/escalation: the flag stays, the transcript stays
--                   preserved; the decision is still recorded + audited.
-- Idempotent: clearing an already-clear flag just re-records the reviewer.
create or replace function public.admin_review_pickup_chat(
  p_admin_id uuid, p_admin_email text, p_chat_id uuid,
  p_decision text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  if p_decision not in ('clear', 'keep_frozen') then
    raise exception 'BAD_DECISION: %', p_decision using errcode = '22023';
  end if;
  select to_jsonb(s) into v_before from (
    select status, report_flag, report_cleared_by, report_cleared_at
      from public.giveaway_pickup_chats where id = p_chat_id
  ) s;
  if v_before is null then
    raise exception 'CHAT_NOT_FOUND: %', p_chat_id using errcode = 'P0002';
  end if;
  if p_decision = 'clear' then
    update public.giveaway_pickup_chats
       set report_flag = false, report_cleared_by = p_admin_id,
           report_cleared_at = now(), updated_at = now()
     where id = p_chat_id;
  end if;
  select to_jsonb(s) into v_after from (
    select status, report_flag, report_cleared_by, report_cleared_at
      from public.giveaway_pickup_chats where id = p_chat_id
  ) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'review_pickup_chat', 'giveaway_chat', p_chat_id::text,
          null, p_reason, jsonb_build_object('decision', p_decision));
  return admin_log_audit(p_admin_id, p_admin_email, 'review_pickup_chat',
           'giveaway_chat', p_chat_id::text, p_reason,
           jsonb_build_object('decision', p_decision), v_before, v_after);
end;
$$;

-- ── 5. execution grants: service_role only ──────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_list_reports(text,text,integer,integer)',
    'admin_list_giveaways(text,text,text,integer,integer)',
    'admin_giveaway_detail(uuid)',
    'admin_giveaway_snapshot(uuid)',
    'admin_hide_giveaway(uuid,text,uuid,text)',
    'admin_restore_giveaway(uuid,text,uuid,text)',
    'admin_close_giveaway(uuid,text,uuid,text)',
    'admin_delete_giveaway(uuid,text,uuid,text)',
    'admin_get_pickup_chat_transcript(uuid,text,uuid)',
    'admin_review_pickup_chat(uuid,text,uuid,text,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0038
-- ============================================================================
