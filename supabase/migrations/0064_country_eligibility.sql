-- ============================================================================
-- 0064 — "we don't know where this ships" is not "it ships everywhere"
--
-- ADDITIVE + IDEMPOTENT.
--
-- `products.country_availability` has always been an array where EMPTY means
-- unrestricted. That was fine while every product was hand-curated by someone
-- who knew the answer. It stops being fine the moment a feed we did not write
-- supplies products with no shipping data at all: an empty array then reads as
-- "ships worldwide", and a product nobody can actually receive passes every
-- country filter in the app.
--
-- So the absence of data gets a name. Three states, and they are not
-- interchangeable:
--
--   listed        these countries, and no others
--   unrestricted  the source positively asserts no restriction
--   unknown       the source said nothing
--
-- Resolution order, product first: a `listed` product answers for itself; an
-- `unknown` one falls back to what an admin has VERIFIED about the merchant
-- (`merchants.shipping_countries`), and if nobody has verified anything the
-- answer is no. Product-level data, when a feed eventually supplies it,
-- overrides the merchant-level fallback by construction.
--
-- The backfill preserves today's behaviour exactly for everything already in
-- the catalog. Only products imported from an affiliate network — which is to
-- say, the ones we genuinely have no shipping evidence for — start as unknown.
-- ============================================================================

-- ── products.country_eligibility ────────────────────────────────────────────

alter table public.products
  add column if not exists country_eligibility text not null default 'unrestricted';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'products_country_eligibility_check'
  ) then
    alter table public.products
      add constraint products_country_eligibility_check
      check (country_eligibility in ('listed', 'unrestricted', 'unknown'));
  end if;
end $$;

-- Backfill, in the order that keeps every existing row meaning what it meant
-- yesterday. Guarded on the default so re-running cannot re-label a row an
-- importer or an admin has since corrected.
update public.products
   set country_eligibility = 'listed'
 where country_eligibility = 'unrestricted'
   and coalesce(array_length(country_availability, 1), 0) > 0;

-- Network-imported products have no shipping evidence and never did; calling
-- them unrestricted was the bug this migration exists to fix. Not tied to any
-- particular network, advertiser or country.
update public.products p
   set country_eligibility = 'unknown'
  from public.merchants m
 where m.id = p.merchant_id
   and m.network is not null
   and p.country_eligibility = 'unrestricted'
   and coalesce(array_length(p.country_availability, 1), 0) = 0;

comment on column public.products.country_eligibility is
  'listed | unrestricted | unknown. `unknown` means the source said nothing '
  'about shipping and must NOT satisfy a country filter on its own — it falls '
  'back to merchants.shipping_countries, which only an admin can set.';

comment on column public.merchants.shipping_countries is
  'ISO-3166-1 alpha-2, uppercase. VERIFIED delivery destinations, set by an '
  'admin. Empty means unverified, not worldwide: it is the fallback answer for '
  'products whose own eligibility is unknown, and an empty fallback answers no.';

create index if not exists products_country_eligibility_idx
  on public.products (country_eligibility)
  where country_eligibility <> 'listed';

-- ── the one definition of "can this reach that country" ─────────────────────
--
-- A function rather than a clause repeated in three query builders, so the API,
-- any future RLS policy and the admin console cannot drift apart on the single
-- question a shopper actually cares about.

create or replace function public.product_ships_to(
  p_eligibility text,
  p_countries text[],
  p_merchant_shipping text[],
  p_country text
) returns boolean
language sql immutable as $$
  select case
    -- No country to check against: nothing to refuse. A user who has not told
    -- us where they are still sees the catalog; this function only ever answers
    -- the question that was asked.
    when p_country is null then true
    -- The product names its own countries. It answers for itself, and the
    -- merchant must also be willing to ship there (an unverified merchant is
    -- not evidence against a product that named the country explicitly).
    when p_eligibility = 'listed' then
      upper(p_country) = any(p_countries)
      and (p_merchant_shipping = '{}' or upper(p_country) = any(p_merchant_shipping))
    -- A positive assertion of no restriction, still subject to the merchant.
    when p_eligibility = 'unrestricted' then
      p_merchant_shipping = '{}' or upper(p_country) = any(p_merchant_shipping)
    -- Unknown: the ONLY evidence is what an admin verified about the merchant.
    -- An empty list here is not "unrestricted", it is "nobody has checked", and
    -- the honest answer to "does this reach Bangladesh" is then no.
    else upper(p_country) = any(p_merchant_shipping)
  end;
$$;

comment on function public.product_ships_to(text, text[], text[], text) is
  'Whether a product can reach a country. Product-level eligibility answers '
  'first; unknown falls back to the merchants verified shipping list, and an '
  'empty fallback is a refusal, not a wildcard.';

-- ── network_discovery_runs.listing_complete ─────────────────────────────────
-- The same signal `product_sync_runs.source_complete` carries, for the other
-- reconciliation: a feed missing from a listing only means "withdrawn" when the
-- whole listing was actually read.

alter table public.network_discovery_runs
  add column if not exists listing_complete boolean not null default true;

comment on column public.network_discovery_runs.listing_complete is
  'False when the feed listing was truncated, mis-shaped or partly unreadable. '
  'Feed removal is skipped for such a run: an unread row is not a withdrawn feed.';

-- ── admin: verified merchant shipping ───────────────────────────────────────
-- Same audited contract as every other admin mutation.

create or replace function public.admin_merchant_snapshot_shipping(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select id, name, shipping_countries, supported_countries
      from public.merchants where id = p_id
  ) s;
$$;

create or replace function public.admin_set_merchant_shipping(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid,
  p_countries text[], p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_clean text[]; v_bad text;
begin
  perform admin_assert_active(p_admin_id);
  v_before := admin_merchant_snapshot_shipping(p_merchant_id);
  if v_before is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;

  -- ISO-3166-1 alpha-2, uppercase, de-duplicated. Rejected rather than
  -- silently dropped: a typo that quietly vanishes is a merchant an operator
  -- believes ships somewhere it does not.
  select array_agg(distinct upper(trim(c)) order by upper(trim(c)))
    into v_clean
    from unnest(coalesce(p_countries, '{}')) c
   where trim(c) <> '';

  select c into v_bad from unnest(coalesce(v_clean, '{}')) c
   where c !~ '^[A-Z]{2}$' limit 1;
  if v_bad is not null then
    raise exception 'INVALID_COUNTRY: % is not an ISO-3166-1 alpha-2 code', v_bad
      using errcode = '22023';
  end if;

  update public.merchants
     set shipping_countries = coalesce(v_clean, '{}'), updated_at = now()
   where id = p_merchant_id;

  v_after := admin_merchant_snapshot_shipping(p_merchant_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'merchant_shipping_set',
           'merchant', p_merchant_id::text, p_reason,
           jsonb_build_object('countries', coalesce(v_clean, '{}')), v_before, v_after);
end;
$$;

-- The network merchant list gains the number that makes the shipping editor
-- worth looking at: how many of this merchant's products are waiting on it.
-- DROP first — a `returns table` signature cannot be widened by REPLACE.
drop function if exists public.admin_list_network_merchants(text);

create or replace function public.admin_list_network_merchants(p_network text default null)
returns table (
  merchant_id uuid, name text, slug text, approved boolean, network text,
  network_advertiser_id text, network_metadata jsonb, network_last_seen_at timestamptz,
  feed_health text, last_synced_at timestamptz,
  sync_enabled boolean, source_kind text, image_rights_default text,
  feed_count bigint, enabled_feed_count bigint, removed_feed_count bigint,
  needs_review_count bigint, declared_products bigint,
  product_count bigint, active_product_count bigint, unknown_shipping_count bigint,
  shipping_countries text[],
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
         (select count(*) from public.products p
           where p.merchant_id = m.id and p.country_eligibility = 'unknown'),
         m.shipping_countries,
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

do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_list_network_merchants(text)',
    'product_ships_to(text,text[],text[],text)',
    'admin_merchant_snapshot_shipping(uuid)',
    'admin_set_merchant_shipping(uuid,text,uuid,text[],text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
  -- `product_ships_to` is a pure predicate with no data in it, and the API runs
  -- it inside queries the app makes on its own behalf.
  execute 'grant execute on function public.product_ships_to(text,text[],text[],text)'
          ' to anon, authenticated;';
end $$;
