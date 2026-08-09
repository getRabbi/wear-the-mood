-- ============================================================================
-- 0063 — Admin RPCs for the affiliate network layer
--
-- ADDITIVE + IDEMPOTENT. Same contract as 0059/0060: security definer,
-- `admin_assert_active` first, before/after snapshots, `admin_log_audit` as the
-- return value, execute revoked from everyone except service_role.
--
-- WHAT THESE DELIBERATELY DO NOT RETURN: any feed URL, any API key, anything
-- from which one could be reconstructed. The console shows a merchant, its
-- feeds by NAME and NUMBER, and their freshness. The authenticated URL is built
-- in the backend at download time and exists nowhere else — so there is no
-- shape of admin request that can leak it, because it is not in the database to
-- leak.
-- ============================================================================

-- ── reads ───────────────────────────────────────────────────────────────────

create or replace function public.admin_list_network_merchants(p_network text default null)
returns table (
  merchant_id uuid, name text, slug text, approved boolean, network text,
  network_advertiser_id text, network_metadata jsonb, network_last_seen_at timestamptz,
  feed_health text, last_synced_at timestamptz,
  sync_enabled boolean, source_kind text, image_rights_default text,
  feed_count bigint, enabled_feed_count bigint, removed_feed_count bigint,
  needs_review_count bigint, declared_products bigint,
  product_count bigint, active_product_count bigint,
  last_run_status text, last_run_complete boolean, last_run_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  select m.id, m.name, m.slug, m.approved, m.network, m.network_advertiser_id,
         m.network_metadata, m.network_last_seen_at, m.feed_health, m.last_synced_at,
         coalesce(c.enabled, false), c.source_kind, c.image_rights_default,
         (select count(*) from public.merchant_feeds f
           where f.merchant_id = m.id and f.removed_at is null),
         (select count(*) from public.merchant_feeds f
           where f.merchant_id = m.id and f.enabled and f.removed_at is null),
         (select count(*) from public.merchant_feeds f
           where f.merchant_id = m.id and f.removed_at is not null),
         (select count(*) from public.merchant_feeds f
           where f.merchant_id = m.id and f.needs_review and f.removed_at is null),
         (select coalesce(sum(f.product_count), 0) from public.merchant_feeds f
           where f.merchant_id = m.id and f.enabled and f.removed_at is null),
         (select count(*) from public.products p where p.merchant_id = m.id),
         (select count(*) from public.products p where p.merchant_id = m.id and p.active),
         r.status, r.source_complete, r.started_at
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
    left join lateral (
      select status, source_complete, started_at from public.product_sync_runs
       where merchant_id = m.id order by started_at desc limit 1
    ) r on true
   where m.network is not null
     and (p_network is null or m.network = p_network)
   order by m.name;
$$;

create or replace function public.admin_list_merchant_feeds(p_merchant_id uuid)
returns table (
  id uuid, network text, network_feed_id text, name text, language text, region text,
  vertical text, product_count integer, source_updated_at timestamptz,
  enabled boolean, needs_review boolean, review_reason text,
  last_seen_at timestamptz, removed_at timestamptz
)
language sql stable security definer set search_path = public
as $$
  -- No URL column exists on this table, so none can be selected. That is the
  -- design, not an omission.
  select f.id, f.network, f.network_feed_id, f.name, f.language, f.region, f.vertical,
         f.product_count, f.source_updated_at, f.enabled, f.needs_review, f.review_reason,
         f.last_seen_at, f.removed_at
    from public.merchant_feeds f
   where f.merchant_id = p_merchant_id
   order by f.removed_at nulls first, f.network_feed_id;
$$;

create or replace function public.admin_list_discovery_runs(p_limit integer default 20)
returns table (
  id uuid, network text, status text, trigger_source text, triggered_by text,
  advertisers_seen integer, advertisers_added integer, feeds_seen integer,
  feeds_added integer, feeds_updated integer, feeds_removed integer,
  errors jsonb, error_message text, started_at timestamptz,
  finished_at timestamptz, duration_ms integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.network, r.status, r.trigger_source, r.triggered_by,
         r.advertisers_seen, r.advertisers_added, r.feeds_seen, r.feeds_added,
         r.feeds_updated, r.feeds_removed, r.errors, r.error_message,
         r.started_at, r.finished_at, r.duration_ms
    from public.network_discovery_runs r
   order by r.started_at desc
   limit greatest(1, least(coalesce(p_limit, 20), 100));
$$;

-- ── writes ──────────────────────────────────────────────────────────────────

create or replace function public.admin_feed_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select id, merchant_id, network_feed_id, name, enabled, needs_review, removed_at
      from public.merchant_feeds where id = p_id
  ) s;
$$;

create or replace function public.admin_set_merchant_feed_state(
  p_admin_id uuid, p_admin_email text, p_feed_id uuid, p_enabled boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_feed_snapshot(p_feed_id);
  if v_before is null then
    raise exception 'FEED_NOT_FOUND: %', p_feed_id using errcode = 'P0002';
  end if;
  -- A feed the network has withdrawn cannot be switched back on by us; it has
  -- to reappear in discovery first.
  if p_enabled and (v_before ->> 'removed_at') is not null then
    raise exception 'FEED_REMOVED: this feed is no longer offered by the network'
      using errcode = '22023';
  end if;
  update public.merchant_feeds
     set enabled = p_enabled, updated_at = now()
   where id = p_feed_id;
  v_after := admin_feed_snapshot(p_feed_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'merchant_feed_set_enabled',
           'merchant_feed', p_feed_id::text, p_reason,
           jsonb_build_object('enabled', p_enabled), v_before, v_after);
end;
$$;

-- Queue a discovery pass. Same enqueue-don't-execute shape as "Sync Now":
-- reading a network account is a network round trip, not a Server Action's job.
create or replace function public.admin_request_network_discovery(
  p_admin_id uuid, p_admin_email text, p_network text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_run uuid;
begin
  perform admin_assert_active(p_admin_id);
  if not coalesce((select enabled from public.feature_flags
                    where key = 'feature_network_discovery'), false) then
    raise exception 'DISCOVERY_OFF: network discovery is disabled' using errcode = '22023';
  end if;

  -- One outstanding request per network; impatient clicking must not become a
  -- queue of identical listing downloads.
  select id into v_run from public.network_discovery_runs
   where network = coalesce(p_network, 'awin') and status = 'queued' limit 1;

  if v_run is null then
    insert into public.network_discovery_runs (network, status, trigger_source, triggered_by)
    values (coalesce(p_network, 'awin'), 'queued', 'admin', p_admin_email)
    returning id into v_run;
  end if;

  return admin_log_audit(p_admin_id, p_admin_email, 'network_discovery_requested',
           'network', coalesce(p_network, 'awin'), null,
           jsonb_build_object('run_id', v_run), null, null);
end;
$$;

create or replace function public.claim_queued_network_discovery()
returns table (run_id uuid, network text, triggered_by text)
language sql security definer set search_path = public
as $$
  update public.network_discovery_runs r
     set status = 'running', started_at = now()
   where r.id = (
     select id from public.network_discovery_runs
      where status = 'queued' order by started_at asc
      for update skip locked limit 1
   )
  returning r.id, r.network, r.triggered_by;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_list_network_merchants(text)',
    'admin_list_merchant_feeds(uuid)',
    'admin_list_discovery_runs(integer)',
    'admin_feed_snapshot(uuid)',
    'admin_set_merchant_feed_state(uuid,text,uuid,boolean,text)',
    'admin_request_network_discovery(uuid,text,text)',
    'claim_queued_network_discovery()'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
