-- 0067 — an operational control for AI image-use rights.
--
-- 0065 split "may we DISPLAY this image" from "may we feed it to a generative
-- render", and left the second one strict. What it did not do is give anybody a
-- way to ANSWER the second question: `image_rights_default` is only ever set by
-- the table's own default, `image_rights_status` is only ever written by the
-- importer, and the console renders both read-only. So the honest answer for
-- every product in production is `unknown`, and there is no supported way to
-- change that short of hand-written SQL.
--
-- This migration adds the control. It does NOT license anything: every value in
-- every environment is exactly what it was before this ran.
--
-- ── the model ───────────────────────────────────────────────────────────────
--
--   merchant_feed_config.image_rights_default   the merchant's DEFAULT
--   products.image_rights_status                this product's CURRENT rights
--   products.image_rights_override  (new)       an EXPLICIT product decision
--
-- Effective rights = coalesce(override, status).
--
-- Why an override column rather than resolving `merchant default` live at read
-- time: `image_rights_status` is also written by the dev seed and by the
-- importer for merchants that have no feed config at all, so making the
-- merchant config the sole source would silently unlicense rows nobody touched.
-- Instead a merchant-default change PROPAGATES — it writes `image_rights_status`
-- for inheriting rows, counts them, and audits the count. A rights decision
-- should be a visible act with a number attached, not a reinterpretation that
-- happens quietly on the next read.
--
-- Overrides are never touched by propagation, and never by the importer.
--
-- Additive and reversible: one nullable column, several new functions, and two
-- existing functions re-pointed at the effective value. Idempotent.

-- ── the explicit product-level decision ─────────────────────────────────────
alter table public.products
  add column if not exists image_rights_override text
    check (image_rights_override in ('unknown', 'licensed', 'restricted'));

comment on column public.products.image_rights_override is
  'Explicit per-product AI image-rights decision. NULL means inherit whatever '
  'image_rights_status currently holds, which merchant-level propagation may '
  'rewrite. A non-null value survives both propagation and the importer.';

comment on column public.products.image_rights_status is
  'This product current AI image rights. Written by the importer from the '
  'merchant default, and by merchant-level propagation for inheriting rows. '
  'NOT the last word: see image_rights_override and '
  'product_effective_image_rights().';

-- Propagation and the console both filter on this, and it is highly selective
-- (almost every row inherits), so a partial index is the right shape.
create index if not exists products_rights_inheriting_idx
  on public.products (merchant_id)
  where image_rights_override is null;

-- ── effective rights: the one definition everything reads ───────────────────
create or replace function public.product_effective_image_rights(p public.products)
returns text language sql stable as $$
  select coalesce(p.image_rights_override, p.image_rights_status)
$$;

comment on function public.product_effective_image_rights(public.products) is
  'The rights value that actually governs this product: an explicit override '
  'where one exists, otherwise its current status.';

grant execute on function public.product_effective_image_rights(public.products)
  to anon, authenticated, service_role;

-- ── the audit snapshot has to be able to SEE the new field ──────────────────
-- Every product mutation records before/after from this. Without the override
-- and the effective value in it, "an admin licensed this product" would audit
-- as a row where nothing visibly changed.
create or replace function public.admin_product_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select p.id, p.title, p.active, p.try_on_status, p.image_rights_status,
           p.image_rights_override,
           public.product_effective_image_rights(p) as effective_image_rights,
           p.stock_status, p.manual_override, p.manual_override_fields,
           p.tryon_image_url, p.tryon_image_source
      from public.products p where p.id = p_id
  ) s;
$$;

-- ── the two gates, re-pointed at the effective value ────────────────────────
-- Neither rule changes. `product_is_servable` still suppresses only a positive
-- refusal; `product_tryon_ready` still demands `licensed`. The only difference
-- is that an explicit product decision is now the thing they read.
create or replace function public.product_is_servable(p public.products)
returns boolean language sql stable as $$
  select p.active
     and coalesce(p.starts_at, '-infinity'::timestamptz) <= now()
     and coalesce(p.ends_at, 'infinity'::timestamptz) > now()
     and p.stock_status <> 'out_of_stock'
     -- DISPLAY rights. `restricted` is a positive refusal and suppresses;
     -- `unknown` does not (0065).
     and public.product_effective_image_rights(p) <> 'restricted'
     and array_length(p.image_urls, 1) >= 1
     and (p.manual_override
          or p.last_synced_at > now() - public.product_staleness_limit())
$$;

create or replace function public.product_tryon_ready(p public.products)
returns boolean language sql stable as $$
  select p.try_on_status = 'ready'
     and public.product_effective_image_rights(p) = 'licensed'
     and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
$$;

-- ── readiness, explained ────────────────────────────────────────────────────
-- The console must not re-implement this. It asks, and renders the answer.
create or replace function public.product_tryon_readiness(p public.products)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'effective_rights', public.product_effective_image_rights(p),
    'rights_ok',        public.product_effective_image_rights(p) = 'licensed',
    'status',           p.try_on_status,
    'status_ok',        p.try_on_status = 'ready',
    'image',            coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]),
    'image_ok',         coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null,
    'active_ok',        p.active,
    'servable',         public.product_is_servable(p),
    'ready',            public.product_tryon_ready(p),
    -- The FIRST thing standing in the way, in the order an operator would fix
    -- them. Null when it is ready.
    'blocked_by', case
      when public.product_tryon_ready(p) then null
      when public.product_effective_image_rights(p) = 'restricted' then 'rights_restricted'
      when public.product_effective_image_rights(p) <> 'licensed' then 'rights_not_licensed'
      when coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is null then 'no_image'
      when p.try_on_status = 'pending' then 'status_pending'
      else 'status_not_ready'
    end
  )
$$;

comment on function public.product_tryon_readiness(public.products) is
  'Per-condition breakdown of product_tryon_ready(), so the console can explain '
  'a refusal instead of re-deriving one.';

grant execute on function public.product_tryon_readiness(public.products)
  to service_role;

-- ── recomputing try_on_status when rights move ──────────────────────────────
-- `try_on_status` is a MATERIALIZED readiness marker: the importer computes it
-- once, from the rights in force at import. So a merchant licensed after import
-- would have licensed rights and a stale `unsupported` status, and nothing
-- would become eligible.
--
-- This is the recomputation, and it applies exactly the rule the importer's
-- `resolve_tryon` and `admin_set_product_tryon_image` already use: licensed
-- rights plus a usable image is ready. Nothing weaker.
--
-- `pending` is left alone in both directions. It means the FEED said "not yet",
-- which is a claim about the garment, not about rights, and rights moving does
-- not answer it.
create or replace function public.product_recompute_tryon_status(p_product_id uuid)
returns text language plpgsql as $$
declare v_status text;
begin
  update public.products p
     set try_on_status = case
           when p.try_on_status = 'pending' then 'pending'
           when public.product_effective_image_rights(p) = 'licensed'
                and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
             then 'ready'
           else 'unsupported'
         end,
         updated_at = now()
   where p.id = p_product_id
  returning p.try_on_status into v_status;
  return v_status;
end;
$$;

comment on function public.product_recompute_tryon_status(uuid) is
  'Re-derives try_on_status from current effective rights and the available '
  'try-on image. Same rule as the importer; never promotes a pending feed claim.';

-- ── what a merchant-level change would touch ────────────────────────────────
-- Read by the console BEFORE the confirmation dialog, so the number in the
-- warning is the real one rather than an estimate.
create or replace function public.admin_merchant_rights_preview(p_merchant_id uuid)
returns table (
  merchant_id uuid, merchant_name text, current_default text,
  inheriting_products bigint, overridden_products bigint,
  would_become_ready bigint, currently_ready bigint, has_feed_config boolean
)
language sql stable security definer set search_path = public
as $$
  select m.id, m.name,
         coalesce(c.image_rights_default, 'unknown'),
         count(*) filter (where p.image_rights_override is null),
         count(*) filter (where p.image_rights_override is not null),
         -- Inheriting rows that are one rights change away from eligible: they
         -- already have a usable image and are not held back by a pending feed
         -- claim. This is the number the warning has to be honest about.
         count(*) filter (
           where p.image_rights_override is null
             and p.try_on_status <> 'pending'
             and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
         ),
         count(*) filter (where public.product_tryon_ready(p)),
         c.merchant_id is not null
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
    left join public.products p on p.merchant_id = m.id
   where m.id = p_merchant_id
   group by m.id, m.name, c.image_rights_default, c.merchant_id;
$$;

-- ── merchant-level: set the default, and propagate ──────────────────────────
create or replace function public.admin_set_merchant_image_rights(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid,
  p_rights text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_before jsonb; v_after jsonb; v_old text; v_name text; v_affected int;
begin
  perform admin_assert_active(p_admin_id);

  if p_rights is null or p_rights not in ('unknown', 'licensed', 'restricted') then
    raise exception 'VALIDATION_ERROR: image rights %', p_rights using errcode = '22023';
  end if;

  select m.name, c.image_rights_default
    into v_name, v_old
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
   where m.id = p_merchant_id;

  if v_name is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;
  -- The default lives on the feed config, which is also what decides whether a
  -- merchant is imported at all. A merchant with no config has no feed and no
  -- default to set; saying so beats inventing a row with a fabricated feed_url.
  if v_old is null then
    raise exception 'NO_FEED_CONFIG: %', p_merchant_id using errcode = 'P0002';
  end if;

  v_before := jsonb_build_object('image_rights_default', v_old, 'merchant', v_name);

  update public.merchant_feed_config
     set image_rights_default = p_rights, updated_at = now()
   where merchant_id = p_merchant_id;

  -- PROPAGATION. Inheriting rows only — an explicit product decision is a
  -- decision, and a merchant-wide change is not permission to discard it.
  update public.products
     set image_rights_status = p_rights, updated_at = now()
   where merchant_id = p_merchant_id
     and image_rights_override is null
     and image_rights_status is distinct from p_rights;
  get diagnostics v_affected = row_count;

  -- Then re-derive readiness for those same rows, so a licensed merchant's
  -- products actually become eligible and a restricted one's actually stop.
  update public.products p
     set try_on_status = case
           when p.try_on_status = 'pending' then 'pending'
           when public.product_effective_image_rights(p) = 'licensed'
                and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
             then 'ready'
           else 'unsupported'
         end,
         updated_at = now()
   where p.merchant_id = p_merchant_id
     and p.image_rights_override is null;

  v_after := jsonb_build_object(
    'image_rights_default', p_rights,
    'merchant', v_name,
    'products_repointed', v_affected
  );

  return admin_log_audit(
    p_admin_id, p_admin_email, 'merchant_set_image_rights',
    'merchant', p_merchant_id::text, p_reason,
    jsonb_build_object('scope', 'merchant_default', 'products_repointed', v_affected),
    v_before, v_after
  );
end;
$$;

comment on function public.admin_set_merchant_image_rights(uuid,text,uuid,text,text) is
  'Set a merchant AI image-rights default and propagate it to products that '
  'inherit. Explicit product overrides are never touched.';

-- ── product-level: set or clear an explicit override ────────────────────────
create or replace function public.admin_set_product_image_rights(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_rights text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_old text; v_status text;
begin
  perform admin_assert_active(p_admin_id);

  -- NULL is a real value here and means "inherit". Anything else must be one of
  -- the three.
  if p_rights is not null and p_rights not in ('unknown', 'licensed', 'restricted') then
    raise exception 'VALIDATION_ERROR: image rights %', p_rights using errcode = '22023';
  end if;

  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  select image_rights_override into v_old from public.products where id = p_product_id;

  update public.products
     set image_rights_override = p_rights, updated_at = now()
   where id = p_product_id;

  -- Readiness follows the new effective rights immediately, by the same rule
  -- the importer uses.
  v_status := public.product_recompute_tryon_status(p_product_id);

  v_after := admin_product_snapshot(p_product_id);

  return admin_log_audit(
    p_admin_id, p_admin_email,
    -- Two distinct actions, because "an admin licensed this product" and "an
    -- admin handed it back to the merchant default" are different decisions and
    -- an audit reader should not have to infer which from a null.
    case when p_rights is null then 'product_clear_image_rights_override'
         else 'product_set_image_rights_override' end,
    'product', p_product_id::text, p_reason,
    jsonb_build_object(
      'scope', 'product_override',
      'previous_override', v_old,
      'new_override', p_rights,
      'try_on_status', v_status
    ),
    v_before, v_after
  );
end;
$$;

comment on function public.admin_set_product_image_rights(uuid,text,uuid,text,text) is
  'Set (or clear, with NULL) the explicit product-level AI image-rights '
  'override. Survives merchant propagation and the importer.';

-- ── the try-on image guard, on EFFECTIVE rights ─────────────────────────────
-- Unchanged in strength. It read the raw column, which would now miss an
-- explicit override in either direction: a product an admin licensed could not
-- be given an image, and one an admin restricted could.
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

  select public.product_effective_image_rights(p) into v_rights
    from public.products p where p.id = p_product_id;

  update public.products
     set tryon_image_url = v_url,
         tryon_image_source = case when v_url is null then null else 'admin' end,
         -- Readiness follows the image AND the rights. Clearing the image drops
         -- the product out of ready rather than leaving a promise with nothing
         -- behind it; setting one on unlicensed imagery does not create a
         -- licence.
         try_on_status = case
           when try_on_status = 'pending' then 'pending'
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

-- ── the console read, widened ───────────────────────────────────────────────
-- Four additions: the merchant's default, this product's override, the
-- resulting effective value, and the readiness breakdown. All computed HERE,
-- from the canonical functions, so the console renders an answer rather than
-- deriving one.
drop function if exists public.admin_list_products(text, uuid, text, text, integer, integer);

create or replace function public.admin_list_products(
  p_search text default null,
  p_merchant_id uuid default null,
  p_status text default null,      -- active | inactive | all
  p_try_on text default null,      -- ready | pending | unsupported
  p_limit integer default 50,
  p_offset integer default 0
) returns table (
  id uuid, external_id text, title text, brand text, category text,
  subcategory text, audience text,
  price_minor bigint, currency char(3), stock_status text, try_on_status text,
  image_rights_status text, active boolean, sponsored boolean,
  merchant_id uuid, merchant_name text, merchant_approved boolean,
  servable boolean, tryon_ready boolean,
  manual_override boolean, manual_override_fields text[],
  tryon_image_url text, tryon_image_source text,
  image_urls text[], last_synced_at timestamptz, last_seen_in_feed_at timestamptz,
  missing_run_count integer, deactivated_by_sync_at timestamptz,
  country_eligibility text, affiliate_host text,
  image_rights_override text, effective_image_rights text,
  merchant_image_rights_default text, tryon_readiness jsonb,
  total_count bigint
)
language sql stable security definer set search_path = public
as $$
  with filtered as (
    select p.*, public.product_is_servable(p) as is_servable,
           public.product_tryon_ready(p) as is_tryon_ready,
           public.product_effective_image_rights(p) as effective_rights,
           public.product_tryon_readiness(p) as readiness,
           m.name as m_name, m.approved as m_approved,
           coalesce(c.image_rights_default, 'unknown') as m_rights_default
      from public.products p
      join public.merchants m on m.id = p.merchant_id
      left join public.merchant_feed_config c on c.merchant_id = m.id
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
         f.subcategory, f.audience,
         f.price_minor, f.currency, f.stock_status, f.try_on_status,
         f.image_rights_status, f.active, f.sponsored,
         f.merchant_id, f.m_name, f.m_approved,
         f.is_servable, f.is_tryon_ready, f.manual_override,
         f.manual_override_fields, f.tryon_image_url, f.tryon_image_source,
         f.image_urls, f.last_synced_at, f.last_seen_in_feed_at,
         f.missing_run_count, f.deactivated_by_sync_at,
         f.country_eligibility,
         case when coalesce(f.affiliate_ref, '') = '' then null
              else split_part(split_part(replace(replace(f.affiliate_ref,
                     'https://', ''), 'http://', ''), '/', 1), '?', 1) end,
         f.image_rights_override, f.effective_rights,
         f.m_rights_default, f.readiness,
         count(*) over ()
    from filtered f
   order by f.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- ── grants ──────────────────────────────────────────────────────────────────
-- Same contract as every other admin mutation: service_role only. A signed-in
-- app user does not become an editor by discovering a function name.
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_set_merchant_image_rights(uuid,text,uuid,text,text)',
    'admin_set_product_image_rights(uuid,text,uuid,text,text)',
    'admin_merchant_rights_preview(uuid)',
    'product_recompute_tryon_status(uuid)',
    'admin_list_products(text,uuid,text,text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
