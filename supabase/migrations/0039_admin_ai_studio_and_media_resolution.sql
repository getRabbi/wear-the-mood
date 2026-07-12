-- ============================================================================
-- 0039 — Admin AI Studio visibility + admin media-URL resolution
-- (ADMIN_GAP_REPORT.md Phase D2 — findings 1.1, 1.2, 2.4, 3.2, 4.1, 5.2)
--
-- The Premium AI Studio (0033) shipped with no admin surface: ai_jobs and
-- generated_images are invisible, and a user's self-report of an unsafe AI
-- output only bumps report_count — nobody can review it. Separately, the admin
-- list RPCs return raw posts.image_url / giveaways.images values, which become
-- R2 object keys (broken previews) the day STORAGE_WRITES flips to r2.
--
-- This migration adds:
--   1. generated_images moderation columns (status/deleted_at/moderated_by/
--      moderation_reason) + a reported-first partial index;
--   2. read RPCs admin_list_ai_jobs + admin_list_generated_images and audited
--      mutations admin_remove/restore_generated_image;
--   3. admin_list_reports v3 — resolves subject_type 'generated_image' (the
--      backend now files a reports row for AI-output self-reports, 5.2);
--   4. media resolution for the console (4.1): admin_list_posts,
--      admin_list_giveaways, admin_giveaway_detail and the report previews
--      prefer the R2 public_url from media_assets over the raw stored value,
--      so previews survive the R2 cutover (legacy rows pass through).
--
-- Idempotent, additive, re-runnable. Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── 1. generated_images — moderation columns (3.2) ──────────────────────────
alter table public.generated_images
  add column if not exists status text not null default 'active'
    check (status in ('active', 'removed')),
  add column if not exists deleted_at        timestamptz,
  add column if not exists moderated_by      uuid references auth.users (id),
  add column if not exists moderation_reason text;

-- Reported-first queue scan (6.2 companion).
create index if not exists generated_images_reported_idx
  on public.generated_images (report_count desc, created_at desc)
  where report_count > 0;

-- Defense-in-depth: the owner's own-row select policy must not show a removed
-- output (the backend filters too; this is the §11 second layer).
drop policy if exists generated_images_select_own on public.generated_images;
create policy generated_images_select_own on public.generated_images
  for select using (auth.uid() = user_id and status = 'active');

-- ── helper: prefer the R2 public CDN url; fall back to the stored value ─────
-- Public sectors only (post/giveaway images). Private sectors are signed at
-- serve time by the backend and are out of scope here (they ride the R2 work).
create or replace function public.admin_public_image(
  p_owner_kind text, p_owner_id uuid, p_role text, p_stored text
) returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select ma.public_url
       from public.media_assets ma
      where ma.owner_kind = p_owner_kind and ma.owner_id = p_owner_id
        and ma.role = p_role and ma.storage_provider = 'r2'
        and ma.visibility = 'public' and ma.deleted_at is null
        and (p_stored is null or ma.legacy_url = p_stored or ma.legacy_url is null)
      order by (ma.legacy_url = p_stored) desc nulls last
      limit 1),
    p_stored);
$$;

-- ── 2a. AI jobs list (1.1) ───────────────────────────────────────────────────
create or replace function public.admin_list_ai_jobs(
  p_search text default null,
  p_type   text default null,
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
    select j.id, j.user_id, j.job_type, j.status, j.quality, j.hd,
           j.credits_reserved, j.credits_charged, j.error_message,
           j.source_item_id, j.style, j.created_at, j.completed_at,
           pr.display_name as user_name, pr.username as user_username,
           u.email as user_email
      from public.ai_jobs j
      join public.profiles pr on pr.id = j.user_id
      join auth.users u on u.id = j.user_id
     where (p_type is null or j.job_type = p_type)
       and (p_status is null or j.status = p_status)
       and (p_search is null or p_search = ''
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or u.email ilike '%' || p_search || '%'
            or j.id::text = p_search
            or j.user_id::text = p_search)
  ),
  page as (
    select b.* from base b
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

-- ── 2b. generated images list (1.2) — reported-first option ─────────────────
create or replace function public.admin_list_generated_images(
  p_reported boolean default null,   -- true = only report_count > 0
  p_status   text default null,      -- active | removed
  p_search   text default null,
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
    select gi.id, gi.user_id, gi.type, gi.output_url, gi.status,
           gi.report_count, gi.moderation_reason, gi.source_item_id,
           gi.job_id, gi.created_at,
           pr.display_name as user_name, pr.username as user_username,
           u.email as user_email
      from public.generated_images gi
      join public.profiles pr on pr.id = gi.user_id
      join auth.users u on u.id = gi.user_id
     where (p_reported is null or not p_reported or gi.report_count > 0)
       and (p_status is null or gi.status = p_status)
       and (p_search is null or p_search = ''
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or u.email ilike '%' || p_search || '%'
            or gi.id::text = p_search
            or gi.user_id::text = p_search)
  ),
  page as (
    select b.* from base b
     order by (b.report_count > 0) desc, b.report_count desc, b.created_at desc
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

-- ── 2c. audited takedown / restore (2.4) ─────────────────────────────────────
create or replace function public.admin_generated_image_snapshot(p_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select to_jsonb(s) from (
    select status, deleted_at, moderated_by, moderation_reason, report_count
      from public.generated_images where id = p_id
  ) s;
$$;

create or replace function public.admin_remove_generated_image(
  p_admin_id uuid, p_admin_email text, p_image_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_generated_image_snapshot(p_image_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_image_id using errcode = 'P0002';
  end if;
  update public.generated_images
     set status = 'removed', deleted_at = coalesce(deleted_at, now()),
         moderated_by = p_admin_id, moderation_reason = p_reason
   where id = p_image_id
   returning user_id into v_owner;
  v_after := admin_generated_image_snapshot(p_image_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'remove_generated_image', 'generated_image',
          p_image_id::text, v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'remove_generated_image',
           'generated_image', p_image_id::text, p_reason, '{}'::jsonb,
           v_before, v_after);
end;
$$;

create or replace function public.admin_restore_generated_image(
  p_admin_id uuid, p_admin_email text, p_image_id uuid, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_owner uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_generated_image_snapshot(p_image_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_image_id using errcode = 'P0002';
  end if;
  update public.generated_images
     set status = 'active', deleted_at = null,
         moderated_by = p_admin_id, moderation_reason = p_reason
   where id = p_image_id
   returning user_id into v_owner;
  v_after := admin_generated_image_snapshot(p_image_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'restore_generated_image', 'generated_image',
          p_image_id::text, v_owner, p_reason, '{}'::jsonb);
  return admin_log_audit(p_admin_id, p_admin_email, 'restore_generated_image',
           'generated_image', p_image_id::text, p_reason, '{}'::jsonb,
           v_before, v_after);
end;
$$;

-- ── 3. admin_list_reports v3 — 'generated_image' + resolved preview images ──
-- Same signature (grants preserved). Post/giveaway preview images now resolve
-- through admin_public_image (4.1).
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
                  when 'generated_image' then (select user_id from public.generated_images where id = r.subject_id)
                  when 'user' then r.subject_id end) as id) x
          left join public.profiles p2 on p2.id = x.id
          left join auth.users u2 on u2.id = x.id
         where x.id is not null),
      'target_preview', case r.subject_type
          when 'post' then (select jsonb_build_object('caption', caption,
                 'image_url', admin_public_image('post', p.id, 'post', p.image_url),
                 'status', status, 'user_id', user_id)
                 from public.posts p where p.id = r.subject_id)
          when 'comment' then (select jsonb_build_object('body', body, 'status', status,
                 'user_id', user_id) from public.comments where id = r.subject_id)
          when 'user' then (select jsonb_build_object('display_name', display_name,
                 'username', username, 'account_status', account_status)
                 from public.profiles where id = r.subject_id)
          when 'giveaway' then (select jsonb_build_object('title', g.title,
                 'image_url', admin_public_image('giveaway', g.id, 'giveaway', g.images->>0),
                 'status', g.status,
                 'hidden_at', g.hidden_at, 'deleted_at', g.deleted_at,
                 'user_id', g.owner_id)
                 from public.giveaways g where g.id = r.subject_id)
          when 'generated_image' then (select jsonb_build_object(
                 'type', gi.type, 'output_url', gi.output_url,
                 'status', gi.status, 'report_count', gi.report_count,
                 'user_id', gi.user_id)
                 from public.generated_images gi where gi.id = r.subject_id)
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

-- ── 4a. admin_list_posts v2 (0026) — resolved preview image ─────────────────
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
    select p.id, p.user_id, p.caption,
           admin_public_image('post', p.id, 'post', p.image_url) as image_url,
           p.status, p.visibility,
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

-- ── 4b. admin_list_giveaways / admin_giveaway_detail v2 (0038) — resolved ───
create or replace function public.admin_list_giveaways(
  p_search text default null,
  p_status text default null,
  p_state  text default null,
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
    select g.id, g.owner_id, g.title, g.description,
           admin_public_image('giveaway', g.id, 'giveaway', g.images->>0) as image_url,
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
        'description', g.description,
        -- Each image element resolves through media_assets by legacy_url;
        -- un-migrated / legacy urls pass through unchanged (4.1).
        'images', coalesce((
          select jsonb_agg(coalesce(ma.public_url, u2.url) order by u2.ord)
            from jsonb_array_elements_text(g.images) with ordinality u2(url, ord)
            left join public.media_assets ma
              on ma.owner_kind = 'giveaway' and ma.owner_id = g.id
             and ma.role = 'giveaway' and ma.legacy_url = u2.url
             and ma.storage_provider = 'r2' and ma.visibility = 'public'
             and ma.deleted_at is null), '[]'::jsonb),
        'size', g.size,
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

-- ── 5. execution grants: service_role only ──────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_public_image(text,uuid,text,text)',
    'admin_list_ai_jobs(text,text,text,integer,integer)',
    'admin_list_generated_images(boolean,text,text,integer,integer)',
    'admin_generated_image_snapshot(uuid)',
    'admin_remove_generated_image(uuid,text,uuid,text)',
    'admin_restore_generated_image(uuid,text,uuid,text)',
    'admin_list_reports(text,text,integer,integer)',
    'admin_list_posts(text,text,boolean,boolean,integer,integer)',
    'admin_list_giveaways(text,text,text,integer,integer)',
    'admin_giveaway_detail(uuid)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0039
-- ============================================================================
