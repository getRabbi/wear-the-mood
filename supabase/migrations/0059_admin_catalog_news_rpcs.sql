-- ============================================================================
-- 0059 — Admin RPCs for the catalog and the newsroom
--
-- ADDITIVE + IDEMPOTENT. Every function follows the SAME contract the admin
-- console has used since 0024/0040, and deliberately adds nothing new to it:
--
--   * security definer, `set search_path = public`
--   * `admin_assert_active(p_admin_id)` FIRST — the console's role check is a
--     UI concern; this is the one that runs inside the database, so a leaked
--     service key still cannot mutate as a deactivated admin
--   * before/after jsonb snapshots
--   * `admin_log_audit(...)` as the return value, so an unaudited mutation is
--     not expressible
--   * execute revoked from public/anon/authenticated, granted to service_role
--     only — these are reachable exclusively through the server-only client
--
-- Read functions are `stable` and take no admin id: the console already gated
-- the page, and a read that logged an audit row per page view would drown the
-- log the writes depend on.
-- ============================================================================

-- ── reads: products ─────────────────────────────────────────────────────────

create or replace function public.admin_list_products(
  p_search text default null,
  p_merchant_id uuid default null,
  p_status text default null,      -- active | inactive | all
  p_try_on text default null,      -- ready | pending | unsupported
  p_limit integer default 50,
  p_offset integer default 0
) returns table (
  id uuid, external_id text, title text, brand text, category text,
  price_minor bigint, currency char(3), stock_status text, try_on_status text,
  image_rights_status text, active boolean, sponsored boolean,
  merchant_id uuid, merchant_name text, merchant_approved boolean,
  servable boolean, manual_override boolean, manual_override_fields text[],
  tryon_image_url text, tryon_image_source text,
  image_urls text[], last_synced_at timestamptz, last_seen_in_feed_at timestamptz,
  missing_run_count integer, deactivated_by_sync_at timestamptz, total_count bigint
)
language sql stable security definer set search_path = public
as $$
  with filtered as (
    -- `product_is_servable(p)` is evaluated HERE, where `p` is still a bare
    -- products row. Casting the widened CTE row back to public.products fails —
    -- it carries the joined merchant columns too — and re-implementing the
    -- servability rule instead would let the console disagree with the RLS
    -- policy about what is visible, which is the one thing it must not do.
    select p.*, public.product_is_servable(p) as is_servable,
           m.name as m_name, m.approved as m_approved
      from public.products p
      join public.merchants m on m.id = p.merchant_id
     where (p_merchant_id is null or p.merchant_id = p_merchant_id)
       and (p_try_on is null or p.try_on_status = p_try_on)
       and (p_status is null or p_status = 'all'
            or (p_status = 'active' and p.active)
            or (p_status = 'inactive' and not p.active))
       and (
         p_search is null or p_search = '' or
         p.title ilike '%' || p_search || '%' or
         p.external_id ilike '%' || p_search || '%' or
         coalesce(p.brand, '') ilike '%' || p_search || '%'
       )
  )
  select f.id, f.external_id, f.title, f.brand, f.category,
         f.price_minor, f.currency, f.stock_status, f.try_on_status,
         f.image_rights_status, f.active, f.sponsored,
         f.merchant_id, f.m_name, f.m_approved,
         f.is_servable, f.manual_override,
         f.manual_override_fields, f.tryon_image_url, f.tryon_image_source,
         f.image_urls, f.last_synced_at, f.last_seen_in_feed_at,
         f.missing_run_count, f.deactivated_by_sync_at,
         count(*) over ()
    from filtered f
   order by f.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.admin_list_merchants()
returns table (
  id uuid, slug text, name text, approved boolean, feed_health text,
  allowed_domains text[], supported_countries text[], shipping_countries text[],
  last_synced_at timestamptz, product_count bigint, active_product_count bigint,
  feed_url_host text, feed_enabled boolean, feed_format text,
  consecutive_failures integer, retry_after timestamptz, locked_at timestamptz,
  image_rights_default text, affiliate_status text, affiliate_configured boolean
)
language sql stable security definer set search_path = public
as $$
  select m.id, m.slug, m.name, m.approved, m.feed_health,
         m.allowed_domains, m.supported_countries, m.shipping_countries,
         m.last_synced_at,
         (select count(*) from public.products p where p.merchant_id = m.id),
         (select count(*) from public.products p where p.merchant_id = m.id and p.active),
         -- The HOST only. A feed URL can carry an API key in its query string,
         -- and this value is rendered in a browser.
         case when c.feed_url is null then null
              else split_part(split_part(replace(replace(c.feed_url, 'https://', ''),
                                                 'http://', ''), '/', 1), '@', -1)
         end,
         coalesce(c.enabled, false), c.feed_format,
         coalesce(c.consecutive_failures, 0), c.retry_after, c.locked_at,
         c.image_rights_default,
         -- The STATUS, never the tag: the affiliate tag identifies the account
         -- that gets paid and must not reach a browser (§40).
         a.status, (a.merchant_id is not null)
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
    left join public.merchant_affiliate_config a on a.merchant_id = m.id
   order by m.name;
$$;

create or replace function public.admin_list_product_sync_runs(
  p_merchant_id uuid default null, p_limit integer default 25
) returns table (
  id uuid, merchant_id uuid, merchant_name text, status text, trigger_source text,
  triggered_by text, dry_run boolean, fetched integer, created integer,
  updated integer, unchanged integer, deactivated integer, reactivated integer,
  skipped integer, errors jsonb, error_message text,
  started_at timestamptz, finished_at timestamptz, duration_ms integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.merchant_id, m.name, r.status, r.trigger_source, r.triggered_by,
         r.dry_run, r.fetched, r.created, r.updated, r.unchanged, r.deactivated,
         r.reactivated, r.skipped, r.errors, r.error_message,
         r.started_at, r.finished_at, r.duration_ms
    from public.product_sync_runs r
    join public.merchants m on m.id = r.merchant_id
   where p_merchant_id is null or r.merchant_id = p_merchant_id
   order by r.started_at desc
   limit greatest(1, least(coalesce(p_limit, 25), 200));
$$;

-- ── writes: products ────────────────────────────────────────────────────────

create or replace function public.admin_product_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select id, title, active, try_on_status, image_rights_status, stock_status,
           manual_override, manual_override_fields, tryon_image_url, tryon_image_source
      from public.products where id = p_id
  ) s;
$$;

-- Publish / unpublish. This is the admin's own decision, so it deliberately
-- CLEARS `deactivated_by_sync_at`: once a human has ruled on a product, a later
-- feed run must not "restore" it as though the importer had retired it.
create or replace function public.admin_set_product_active(
  p_admin_id uuid, p_admin_email text, p_product_id uuid, p_active boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  update public.products
     set active = p_active, deactivated_by_sync_at = null,
         missing_run_count = 0, updated_at = now()
   where id = p_product_id;
  v_after := admin_product_snapshot(p_product_id);
  return admin_log_audit(p_admin_id, p_admin_email,
           case when p_active then 'product_publish' else 'product_unpublish' end,
           'product', p_product_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- Manual override. `p_fields` empty freezes the whole row; a list freezes only
-- those fields. Clearing it hands the row back to the importer.
create or replace function public.admin_set_product_override(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_enabled boolean, p_fields text[], p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  update public.products
     set manual_override = p_enabled,
         manual_override_fields = case when p_enabled then coalesce(p_fields, '{}') else '{}' end,
         manual_override_by = case when p_enabled then p_admin_email else null end,
         manual_override_at = case when p_enabled then now() else null end,
         updated_at = now()
   where id = p_product_id;
  v_after := admin_product_snapshot(p_product_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'product_set_override',
           'product', p_product_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- The preferred try-on image. Validated in the DATABASE as well as the console:
-- this URL is handed to a paid render, and "the UI checked it" is not a
-- guarantee when the UI is not the only caller.
create or replace function public.admin_set_product_tryon_image(
  p_admin_id uuid, p_admin_email text, p_product_id uuid, p_image_url text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_url text; v_rights text;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  v_url := nullif(btrim(coalesce(p_image_url, '')), '');
  if v_url is not null and v_url !~* '^https?://[^/\s]+/' then
    raise exception 'INVALID_IMAGE_URL: must be an absolute http(s) URL'
      using errcode = '22023';
  end if;
  select image_rights_status into v_rights from public.products where id = p_product_id;

  update public.products
     set tryon_image_url = v_url,
         tryon_image_source = case when v_url is null then null else 'admin' end,
         -- Readiness follows the image AND the rights. Clearing the image drops
         -- the product out of ready rather than leaving a promise with nothing
         -- behind it; setting one on unlicensed imagery does not create a
         -- licence.
         try_on_status = case
           when v_url is null then 'unsupported'
           when v_rights = 'licensed' then 'ready'
           else 'unsupported'
         end,
         updated_at = now()
   where id = p_product_id;
  v_after := admin_product_snapshot(p_product_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'product_set_tryon_image',
           'product', p_product_id::text, p_reason,
           jsonb_build_object('rights', v_rights), v_before, v_after);
end;
$$;

-- ── writes: merchants ───────────────────────────────────────────────────────

create or replace function public.admin_merchant_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select m.id, m.name, m.approved, m.feed_health,
           c.enabled as feed_enabled, c.image_rights_default
      from public.merchants m
      left join public.merchant_feed_config c on c.merchant_id = m.id
     where m.id = p_id
  ) s;
$$;

create or replace function public.admin_set_merchant_approved(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid, p_approved boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_merchant_snapshot(p_merchant_id);
  if v_before is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;
  update public.merchants set approved = p_approved, updated_at = now() where id = p_merchant_id;
  v_after := admin_merchant_snapshot(p_merchant_id);
  return admin_log_audit(p_admin_id, p_admin_email,
           case when p_approved then 'merchant_approve' else 'merchant_disable' end,
           'merchant', p_merchant_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

create or replace function public.admin_set_merchant_feed_enabled(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid, p_enabled boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_merchant_snapshot(p_merchant_id);
  if v_before is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.merchant_feed_config where merchant_id = p_merchant_id) then
    raise exception 'NO_FEED_CONFIG: merchant % has no feed configured', p_merchant_id
      using errcode = 'P0002';
  end if;
  update public.merchant_feed_config
     set enabled = p_enabled,
         -- Enabling clears the backoff: an operator switching a feed back on is
         -- explicitly asking for it to be tried again now.
         consecutive_failures = case when p_enabled then 0 else consecutive_failures end,
         retry_after = case when p_enabled then null else retry_after end,
         updated_at = now()
   where merchant_id = p_merchant_id;
  v_after := admin_merchant_snapshot(p_merchant_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'merchant_set_feed_enabled',
           'merchant', p_merchant_id::text, p_reason,
           jsonb_build_object('enabled', p_enabled), v_before, v_after);
end;
$$;

-- Clear a stuck lock. Bounded to locks older than the run timeout, so this
-- cannot be used to stomp on a run that is genuinely in progress.
create or replace function public.admin_clear_feed_lock(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb;
begin
  perform admin_assert_active(p_admin_id);
  select to_jsonb(s) into v_before from (
    select merchant_id, locked_at, locked_by from public.merchant_feed_config
     where merchant_id = p_merchant_id
  ) s;
  update public.merchant_feed_config
     set locked_at = null, locked_by = null, updated_at = now()
   where merchant_id = p_merchant_id
     and locked_at is not null
     and locked_at < now() - interval '30 minutes';
  return admin_log_audit(p_admin_id, p_admin_email, 'merchant_clear_feed_lock',
           'merchant', p_merchant_id::text, null, '{}'::jsonb, v_before,
           (select to_jsonb(s) from (
              select merchant_id, locked_at, locked_by from public.merchant_feed_config
               where merchant_id = p_merchant_id) s));
end;
$$;

-- ── reads + writes: newsroom ────────────────────────────────────────────────

create or replace function public.admin_list_news_sources()
returns table (
  id uuid, slug text, name text, publisher text, feed_url text, feed_kind text,
  enabled boolean, priority integer, category text, auto_publish boolean,
  health text, consecutive_failures integer, retry_after timestamptz,
  last_success_at timestamptz, item_count bigint, pending_review_count bigint
)
language sql stable security definer set search_path = public
as $$
  select s.id, s.slug, s.name, s.publisher, s.feed_url, s.feed_kind,
         s.enabled, s.priority, s.category, s.auto_publish, s.health,
         s.consecutive_failures, s.retry_after, s.last_success_at,
         (select count(*) from public.news_items n where n.source_id = s.id),
         (select count(*) from public.news_items n
           where n.source_id = s.id and n.status = 'review_required')
    from public.news_sources s
   order by s.priority asc, s.name asc;
$$;

create or replace function public.admin_list_news_items(
  p_status text default null, p_source_id uuid default null,
  p_search text default null, p_limit integer default 50, p_offset integer default 0
) returns table (
  id uuid, title text, summary text, source text, url text, canonical_url text,
  image_url text, published_at timestamptz, status text, source_id uuid,
  source_name text, author text, attribution text, created_at timestamptz,
  total_count bigint
)
language sql stable security definer set search_path = public
as $$
  with filtered as (
    select n.*, s.name as s_name
      from public.news_items n
      left join public.news_sources s on s.id = n.source_id
     where (p_status is null or p_status = 'all' or n.status = p_status)
       and (p_source_id is null or n.source_id = p_source_id)
       and (p_search is null or p_search = '' or n.title ilike '%' || p_search || '%')
  )
  select f.id, f.title, f.summary, f.source, f.url, f.canonical_url, f.image_url,
         f.published_at, f.status, f.source_id, f.s_name, f.author, f.attribution,
         f.created_at, count(*) over ()
    from filtered f
   order by coalesce(f.published_at, f.created_at) desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

create or replace function public.admin_list_news_sync_runs(p_limit integer default 25)
returns table (
  id uuid, source_id uuid, source_name text, status text, trigger_source text,
  triggered_by text, dry_run boolean, fetched integer, created integer,
  updated integer, duplicates integer, skipped integer, errors jsonb,
  error_message text, started_at timestamptz, finished_at timestamptz, duration_ms integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.source_id, s.name, r.status, r.trigger_source, r.triggered_by,
         r.dry_run, r.fetched, r.created, r.updated, r.duplicates, r.skipped,
         r.errors, r.error_message, r.started_at, r.finished_at, r.duration_ms
    from public.news_sync_runs r
    left join public.news_sources s on s.id = r.source_id
   order by r.started_at desc
   limit greatest(1, least(coalesce(p_limit, 25), 200));
$$;

create or replace function public.admin_news_source_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select id, slug, name, enabled, priority, category, auto_publish, health
      from public.news_sources where id = p_id
  ) s;
$$;

create or replace function public.admin_upsert_news_source(
  p_admin_id uuid, p_admin_email text, p_source_id uuid,
  p_slug text, p_name text, p_feed_url text, p_publisher text,
  p_category text, p_priority integer, p_auto_publish boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_id uuid;
begin
  perform admin_assert_active(p_admin_id);
  -- Feeds are fetched server-side by the ingester; an http or non-URL value
  -- would be a request we make on somebody else's behalf.
  if coalesce(p_feed_url, '') !~* '^https://[^/\s]+' then
    raise exception 'INVALID_FEED_URL: must be an absolute https URL' using errcode = '22023';
  end if;
  v_before := admin_news_source_snapshot(p_source_id);
  if p_source_id is null then
    insert into public.news_sources (slug, name, feed_url, publisher, category,
                                     priority, auto_publish, enabled)
    -- Created DISABLED and unpublished regardless of what was asked for: a new
    -- source is reviewed before it ingests, which is the whole point of an
    -- approved-source list.
    values (p_slug, p_name, p_feed_url, p_publisher, p_category,
            coalesce(p_priority, 100), coalesce(p_auto_publish, false), false)
    returning id into v_id;
  else
    v_id := p_source_id;
    update public.news_sources
       set slug = p_slug, name = p_name, feed_url = p_feed_url, publisher = p_publisher,
           category = p_category, priority = coalesce(p_priority, priority),
           auto_publish = coalesce(p_auto_publish, auto_publish), updated_at = now()
     where id = v_id;
  end if;
  v_after := admin_news_source_snapshot(v_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'news_source_upsert',
           'news_source', v_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

create or replace function public.admin_set_news_source_enabled(
  p_admin_id uuid, p_admin_email text, p_source_id uuid, p_enabled boolean, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_news_source_snapshot(p_source_id);
  if v_before is null then
    raise exception 'SOURCE_NOT_FOUND: %', p_source_id using errcode = 'P0002';
  end if;
  update public.news_sources
     set enabled = p_enabled,
         consecutive_failures = case when p_enabled then 0 else consecutive_failures end,
         retry_after = case when p_enabled then null else retry_after end,
         health = case when p_enabled then 'ok' else health end,
         updated_at = now()
   where id = p_source_id;
  v_after := admin_news_source_snapshot(p_source_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'news_source_set_enabled',
           'news_source', p_source_id::text, p_reason,
           jsonb_build_object('enabled', p_enabled), v_before, v_after);
end;
$$;

create or replace function public.admin_news_item_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select id, title, status, source_id, canonical_url from public.news_items where id = p_id
  ) s;
$$;

create or replace function public.admin_set_news_item_status(
  p_admin_id uuid, p_admin_email text, p_item_id uuid, p_status text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  if p_status not in ('draft', 'review_required', 'published', 'archived') then
    raise exception 'INVALID_STATUS: %', p_status using errcode = '22023';
  end if;
  v_before := admin_news_item_snapshot(p_item_id);
  if v_before is null then
    raise exception 'ITEM_NOT_FOUND: %', p_item_id using errcode = 'P0002';
  end if;
  update public.news_items
     set status = p_status, published_by = p_admin_email, published_state_at = now()
   where id = p_item_id;
  v_after := admin_news_item_snapshot(p_item_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'news_item_set_status',
           'news_item', p_item_id::text, p_reason,
           jsonb_build_object('status', p_status), v_before, v_after);
end;
$$;

-- Editing stores a SUMMARY and a headline. There is deliberately no parameter
-- for article body text: the schema has nowhere to put it, and that is what
-- keeps "no full copyrighted article copying" true by construction.
create or replace function public.admin_update_news_item(
  p_admin_id uuid, p_admin_email text, p_item_id uuid,
  p_title text, p_summary text, p_attribution text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_news_item_snapshot(p_item_id);
  if v_before is null then
    raise exception 'ITEM_NOT_FOUND: %', p_item_id using errcode = 'P0002';
  end if;
  if length(coalesce(p_summary, '')) > 1200 then
    raise exception 'SUMMARY_TOO_LONG: a summary is not an article' using errcode = '22023';
  end if;
  update public.news_items
     set title = coalesce(nullif(btrim(p_title), ''), title),
         summary = nullif(btrim(coalesce(p_summary, '')), ''),
         attribution = nullif(btrim(coalesce(p_attribution, '')), '')
   where id = p_item_id;
  v_after := admin_news_item_snapshot(p_item_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'news_item_update',
           'news_item', p_item_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- ── lock down ───────────────────────────────────────────────────────────────
-- Same posture as 0040: nothing here is callable by anon or by a logged-in app
-- user. The only caller is the console's server-only service-role client.

do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_list_products(text,uuid,text,text,integer,integer)',
    'admin_list_merchants()',
    'admin_list_product_sync_runs(uuid,integer)',
    'admin_product_snapshot(uuid)',
    'admin_set_product_active(uuid,text,uuid,boolean,text)',
    'admin_set_product_override(uuid,text,uuid,boolean,text[],text)',
    'admin_set_product_tryon_image(uuid,text,uuid,text,text)',
    'admin_merchant_snapshot(uuid)',
    'admin_set_merchant_approved(uuid,text,uuid,boolean,text)',
    'admin_set_merchant_feed_enabled(uuid,text,uuid,boolean,text)',
    'admin_clear_feed_lock(uuid,text,uuid)',
    'admin_list_news_sources()',
    'admin_list_news_items(text,uuid,text,integer,integer)',
    'admin_list_news_sync_runs(integer)',
    'admin_news_source_snapshot(uuid)',
    'admin_upsert_news_source(uuid,text,uuid,text,text,text,text,text,integer,boolean,text)',
    'admin_set_news_source_enabled(uuid,text,uuid,boolean,text)',
    'admin_news_item_snapshot(uuid)',
    'admin_set_news_item_status(uuid,text,uuid,text,text)',
    'admin_update_news_item(uuid,text,uuid,text,text,text,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
