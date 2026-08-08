-- ============================================================================
-- 0060 — "Sync Now": admin-queued sync runs
--
-- ADDITIVE + IDEMPOTENT.
--
-- The console does NOT import from its own process. Ingestion is the backend's
-- job: it fetches somebody else's server, can take minutes, and a Next.js
-- Server Action is the wrong lifetime to hold that open. So "Sync Now" ENQUEUES
-- — it writes a run row with status `queued`, and the existing cron/worker
-- claims it on its next pass.
--
-- The queue is the run-history table itself rather than a second one, so an
-- admin-triggered run and a cron run are the same object: same counts, same
-- errors, same place to look. `trigger_source` is what tells them apart.
-- ============================================================================

-- `queued` joins the existing statuses. No CHECK constraint exists on these
-- columns, so this is a documentation change plus the functions below.
comment on column public.product_sync_runs.status is
  'queued | running | success | partial | failed | skipped';
comment on column public.news_sync_runs.status is
  'queued | running | success | partial | failed | skipped';

create index if not exists product_sync_runs_queued_idx
  on public.product_sync_runs (started_at) where status = 'queued';
create index if not exists news_sync_runs_queued_idx
  on public.news_sync_runs (started_at) where status = 'queued';

-- ── request a product sync ──────────────────────────────────────────────────

create or replace function public.admin_request_product_sync(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid, p_dry_run boolean
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_run uuid; v_enabled boolean; v_approved boolean;
begin
  perform admin_assert_active(p_admin_id);

  -- The global kill switch is enforced HERE as well as in the cron. A button
  -- that queues work the runner will refuse is worse than a disabled button:
  -- it reports success and nothing happens.
  if not coalesce((select enabled from public.feature_flags
                    where key = 'feature_product_automation'), false) then
    raise exception 'AUTOMATION_OFF: product automation is disabled'
      using errcode = '22023';
  end if;

  select c.enabled, m.approved into v_enabled, v_approved
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
   where m.id = p_merchant_id;

  if v_approved is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;
  if not v_approved then
    raise exception 'MERCHANT_NOT_APPROVED: %', p_merchant_id using errcode = '22023';
  end if;
  if not coalesce(v_enabled, false) then
    raise exception 'FEED_DISABLED: merchant % has no enabled feed', p_merchant_id
      using errcode = '22023';
  end if;

  -- One outstanding request per merchant. Ten impatient clicks must not become
  -- ten runs against somebody else's rate limit.
  select id into v_run from public.product_sync_runs
   where merchant_id = p_merchant_id and status = 'queued' limit 1;

  if v_run is null then
    insert into public.product_sync_runs
      (merchant_id, status, trigger_source, triggered_by, dry_run)
    values (p_merchant_id, 'queued', 'admin', p_admin_email, coalesce(p_dry_run, true))
    returning id into v_run;
  end if;

  return admin_log_audit(p_admin_id, p_admin_email, 'product_sync_requested',
           'merchant', p_merchant_id::text, null,
           jsonb_build_object('run_id', v_run, 'dry_run', coalesce(p_dry_run, true)),
           null, null);
end;
$$;

-- ── request a news sync ─────────────────────────────────────────────────────

create or replace function public.admin_request_news_sync(
  p_admin_id uuid, p_admin_email text, p_source_id uuid, p_dry_run boolean
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_run uuid;
begin
  perform admin_assert_active(p_admin_id);

  if not coalesce((select enabled from public.feature_flags
                    where key = 'feature_news_automation'), false) then
    raise exception 'AUTOMATION_OFF: news automation is disabled' using errcode = '22023';
  end if;

  -- A specific source must exist AND be enabled. A disabled source must not
  -- ingest by any route, including a button.
  if p_source_id is not null then
    if not exists (select 1 from public.news_sources where id = p_source_id) then
      raise exception 'SOURCE_NOT_FOUND: %', p_source_id using errcode = 'P0002';
    end if;
    if not exists (select 1 from public.news_sources where id = p_source_id and enabled) then
      raise exception 'SOURCE_DISABLED: %', p_source_id using errcode = '22023';
    end if;
  end if;

  select id into v_run from public.news_sync_runs
   where status = 'queued' and source_id is not distinct from p_source_id limit 1;

  if v_run is null then
    insert into public.news_sync_runs (source_id, status, trigger_source, triggered_by, dry_run)
    values (p_source_id, 'queued', 'admin', p_admin_email, coalesce(p_dry_run, true))
    returning id into v_run;
  end if;

  return admin_log_audit(p_admin_id, p_admin_email, 'news_sync_requested',
           'news_source', coalesce(p_source_id::text, 'all'), null,
           jsonb_build_object('run_id', v_run, 'dry_run', coalesce(p_dry_run, true)),
           null, null);
end;
$$;

-- ── claim helpers (used by the workers, service-role only) ──────────────────
-- A conditional UPDATE, so two workers racing cannot both claim one request.

create or replace function public.claim_queued_product_sync()
returns table (run_id uuid, merchant_id uuid, dry_run boolean, triggered_by text)
language sql security definer set search_path = public
as $$
  update public.product_sync_runs r
     set status = 'running', started_at = now()
   where r.id = (
     select id from public.product_sync_runs
      where status = 'queued' order by started_at asc
      for update skip locked limit 1
   )
  returning r.id, r.merchant_id, r.dry_run, r.triggered_by;
$$;

create or replace function public.claim_queued_news_sync()
returns table (run_id uuid, source_id uuid, dry_run boolean, triggered_by text)
language sql security definer set search_path = public
as $$
  update public.news_sync_runs r
     set status = 'running', started_at = now()
   where r.id = (
     select id from public.news_sync_runs
      where status = 'queued' order by started_at asc
      for update skip locked limit 1
   )
  returning r.id, r.source_id, r.dry_run, r.triggered_by;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_request_product_sync(uuid,text,uuid,boolean)',
    'admin_request_news_sync(uuid,text,uuid,boolean)',
    'claim_queued_product_sync()',
    'claim_queued_news_sync()'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
