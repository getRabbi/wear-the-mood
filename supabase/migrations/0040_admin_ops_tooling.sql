-- ============================================================================
-- 0040 — Admin ops tooling: flags, presets, AI cost, global billing views
-- (ADMIN_GAP_REPORT.md Phase D3 — findings 1.5, 1.6, 1.7, 1.8, 2.5, 6.1)
--
-- Until now these were SSH-and-SQL jobs:
--   * feature_flags (the app's real kill-switches) had no console toggle;
--   * tryon_model_presets go live by hand-editing image_url/is_active (0035
--     even added a safety net against bad manual activation);
--   * ai_usage_log (AI cost = CLAUDE.md §14 "risk #1") had no rollup view;
--   * credit_transactions / top_up_purchases had no global view, and try-on
--     jobs had no per-user list for credit disputes.
--
-- Adds audited mutation RPCs (flag toggle, preset edit/activate with an
-- image-required guard) + read RPCs (AI daily cost rollup, global credit
-- ledger, top-up purchases, per-user try-on jobs) and the ai_usage_log
-- time index the rollup needs. Idempotent, additive. Dev first, then prod.
-- ============================================================================

-- Rollup + global-ledger scans.
create index if not exists ai_usage_log_created_idx
  on public.ai_usage_log (created_at desc);
create index if not exists credit_transactions_created_idx
  on public.credit_transactions (created_at desc);

-- ── feature flags: audited console toggle (1.6) ─────────────────────────────
-- Toggle only — flags are CREATED by migrations (each with its kill-switch
-- semantics reviewed), never ad-hoc from the console.
create or replace function public.admin_set_feature_flag(
  p_admin_id uuid, p_admin_email text, p_key text, p_enabled boolean
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  select to_jsonb(s) into v_before from (
    select key, enabled from public.feature_flags where key = p_key
  ) s;
  if v_before is null then
    raise exception 'FLAG_NOT_FOUND: %', p_key using errcode = 'P0002';
  end if;
  update public.feature_flags
     set enabled = p_enabled, updated_at = now()
   where key = p_key;
  select to_jsonb(s) into v_after from (
    select key, enabled from public.feature_flags where key = p_key
  ) s;
  return admin_log_audit(p_admin_id, p_admin_email, 'set_feature_flag',
           'feature_flag', p_key, null, '{}'::jsonb, v_before, v_after);
end;
$$;

-- ── try-on model presets: audited edit + guarded activation (2.5) ───────────
create or replace function public.admin_preset_snapshot(p_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select to_jsonb(s) from (
    select name, image_url, is_active, sort_order
      from public.tryon_model_presets where id = p_id
  ) s;
$$;

create or replace function public.admin_update_model_preset(
  p_admin_id uuid, p_admin_email text, p_preset_id uuid,
  p_name text, p_image_url text, p_sort_order int
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  if p_name is null or btrim(p_name) = '' then
    raise exception 'NAME_REQUIRED' using errcode = '23514';
  end if;
  v_before := admin_preset_snapshot(p_preset_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_preset_id using errcode = 'P0002';
  end if;
  update public.tryon_model_presets
     set name = p_name,
         image_url = nullif(btrim(coalesce(p_image_url, '')), ''),
         sort_order = coalesce(p_sort_order, sort_order),
         -- 0035 safety net, enforced here too: a preset can never stay active
         -- with a blank image.
         is_active = case
           when nullif(btrim(coalesce(p_image_url, '')), '') is null then false
           else is_active end
   where id = p_preset_id;
  v_after := admin_preset_snapshot(p_preset_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'update_model_preset',
           'tryon_model_preset', p_preset_id::text, null, '{}'::jsonb,
           v_before, v_after);
end;
$$;

create or replace function public.admin_set_preset_active(
  p_admin_id uuid, p_admin_email text, p_preset_id uuid, p_active boolean
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_image text;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_preset_snapshot(p_preset_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_preset_id using errcode = 'P0002';
  end if;
  if p_active then
    select image_url into v_image
      from public.tryon_model_presets where id = p_preset_id;
    if v_image is null or btrim(v_image) = '' then
      raise exception 'IMAGE_REQUIRED: preset % has no image_url', p_preset_id
        using errcode = '23514';
    end if;
  end if;
  update public.tryon_model_presets
     set is_active = p_active
   where id = p_preset_id;
  v_after := admin_preset_snapshot(p_preset_id);
  return admin_log_audit(p_admin_id, p_admin_email,
           case when p_active then 'activate_model_preset'
                else 'deactivate_model_preset' end,
           'tryon_model_preset', p_preset_id::text, null, '{}'::jsonb,
           v_before, v_after);
end;
$$;

-- ── AI cost rollup (1.7, §14) ────────────────────────────────────────────────
create or replace function public.admin_ai_cost_daily(p_days int default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 90);
  v_result jsonb;
begin
  with base as (
    select date_trunc('day', created_at)::date as day, provider,
           count(*) as calls,
           coalesce(sum(input_tokens), 0) as input_tokens,
           coalesce(sum(output_tokens), 0) as output_tokens,
           coalesce(sum(images), 0) as images,
           coalesce(sum(estimated_usd), 0)::numeric(12,4) as est_usd,
           count(*) filter (where success is false) as failures
      from public.ai_usage_log
     where created_at >= now() - make_interval(days => v_days)
     group by 1, 2
  )
  select jsonb_build_object(
    'days', coalesce((select jsonb_agg(to_jsonb(b) order by b.day desc, b.provider)
                        from base b), '[]'::jsonb),
    'today_usd', coalesce((select sum(est_usd) from base
                            where day = current_date), 0),
    'last7_usd', coalesce((select sum(est_usd) from base
                            where day >= current_date - 6), 0),
    'total_usd', coalesce((select sum(est_usd) from base), 0)
  ) into v_result;
  return v_result;
end;
$$;

-- ── global credit ledger + top-ups (1.8, 6.1) ───────────────────────────────
create or replace function public.admin_list_credit_transactions(
  p_search text default null,
  p_reason text default null,
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
    select t.id, t.user_id, t.delta, t.reason, t.balance_after, t.ref,
           t.created_at,
           pr.display_name as user_name, pr.username as user_username,
           u.email as user_email
      from public.credit_transactions t
      join public.profiles pr on pr.id = t.user_id
      join auth.users u on u.id = t.user_id
     where (p_reason is null or t.reason = p_reason)
       and (p_search is null or p_search = ''
            or pr.username ilike '%' || p_search || '%'
            or pr.display_name ilike '%' || p_search || '%'
            or u.email ilike '%' || p_search || '%'
            or t.user_id::text = p_search)
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

create or replace function public.admin_list_top_up_purchases(
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
  with page as (
    select tp.id, tp.user_id, tp.sku, tp.credits, tp.price_usd, tp.store,
           tp.store_txn_id, tp.created_at,
           pr.display_name as user_name, u.email as user_email
      from public.top_up_purchases tp
      join public.profiles pr on pr.id = tp.user_id
      join auth.users u on u.id = tp.user_id
     order by tp.created_at desc
     limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'total', (select count(*) from public.top_up_purchases),
    'limit', v_limit,
    'offset', v_offset,
    'rows', coalesce((select jsonb_agg(to_jsonb(p)) from page p), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- ── per-user try-on jobs (1.5 — credit-dispute triage on user detail) ───────
create or replace function public.admin_list_tryon_jobs(
  p_user_id uuid,
  p_limit   int default 10
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(greatest(coalesce(p_limit, 10), 1), 50);
begin
  return coalesce((
    select jsonb_agg(to_jsonb(j) order by j.created_at desc)
      from (
        select id, status, hd, model_source, provider, error, created_at
          from public.tryon_jobs
         where user_id = p_user_id
         order by created_at desc
         limit v_limit
      ) j), '[]'::jsonb);
end;
$$;

-- ── execution grants: service_role only ─────────────────────────────────────
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_set_feature_flag(uuid,text,text,boolean)',
    'admin_preset_snapshot(uuid)',
    'admin_update_model_preset(uuid,text,uuid,text,text,integer)',
    'admin_set_preset_active(uuid,text,uuid,boolean)',
    'admin_ai_cost_daily(integer)',
    'admin_list_credit_transactions(text,text,integer,integer)',
    'admin_list_top_up_purchases(integer,integer)',
    'admin_list_tryon_jobs(uuid,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0040
-- ============================================================================
