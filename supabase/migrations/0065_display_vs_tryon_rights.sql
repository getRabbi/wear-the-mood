-- 0065 — showing a product and feeding it to an AI are different permissions.
--
-- `product_is_servable()` is the single definition of "safe to show", used by
-- the RLS policy AND the API so the two cannot drift. It required
-- `image_rights_status = 'licensed'`, which quietly made one question answer two
-- unrelated ones:
--
--   * may we DISPLAY this product's image next to its affiliate link?
--   * may we feed that image to a paid AI render as try-on input?
--
-- An affiliate programme supplies product imagery precisely so it can be shown
-- alongside the tracked link — that is what the feed is for. Using the same
-- image as INPUT to a generative render is a different and stronger permission
-- that no feed grants implicitly. Collapsing them meant the honest answer for a
-- network product (`unknown` AI rights) also hid it from ordinary shopping, so
-- the entire affiliate catalog was unservable by construction.
--
-- This migration splits the two and leaves the AI side exactly as strict as it
-- was. Nothing here makes a try-on more likely; `product_tryon_ready()` still
-- demands `licensed`, and `try_on_status` still has to have been earned.
--
-- Also fixes a second way the curated catalog would have disappeared: staleness.
-- Idempotent; safe to re-run.

-- ── display vs AI rights, and staleness for curated rows ────────────────────
create or replace function public.product_is_servable(p public.products)
returns boolean language sql stable as $$
  select p.active
     and coalesce(p.starts_at, '-infinity'::timestamptz) <= now()
     and coalesce(p.ends_at, 'infinity'::timestamptz) > now()
     and p.stock_status <> 'out_of_stock'
     -- DISPLAY rights. `restricted` is a positive refusal and still suppresses.
     -- `unknown` no longer does: see the header. The human gate for display is
     -- merchant approval, which the RLS policy already requires and which only
     -- an admin can grant.
     and p.image_rights_status <> 'restricted'
     and array_length(p.image_urls, 1) >= 1
     -- Staleness is a claim about a FEED — "the importer has not reconfirmed
     -- this price recently". A row a human froze makes no such claim, and
     -- nothing is ever going to reconfirm it because that is what freezing it
     -- means. Expiring those would delete the curated catalog seven days after
     -- it was curated, with automation off and nothing to notice.
     and (p.manual_override
          or p.last_synced_at > now() - public.product_staleness_limit())
$$;

comment on function public.product_is_servable(public.products) is
  'Safe to DISPLAY in shopping. Shared by the RLS policy and the API. Says '
  'nothing about AI try-on eligibility — that is product_tryon_ready().';

-- ── the AI gate, stated separately and deliberately narrower ────────────────
-- Everything the old combined check demanded of rights, kept, plus the two
-- conditions that were never expressible before: try-on must have been earned
-- (`ready`, never `pending`), and there must be an actual image to seed with.
create or replace function public.product_tryon_ready(p public.products)
returns boolean language sql stable as $$
  select p.try_on_status = 'ready'
     and p.image_rights_status = 'licensed'
     and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
$$;

comment on function public.product_tryon_ready(public.products) is
  'May this product be used as AI try-on INPUT. Requires licensed image rights '
  'and an earned ready status; unknown/pending are never ready.';

-- Callable by the app for filtering, exactly like product_ships_to. It grants
-- nothing: it only reports what the columns already say.
grant execute on function public.product_tryon_ready(public.products)
  to anon, authenticated, service_role;

-- ── admin: edit the fields a human is allowed to correct ────────────────────
-- The console could publish, unpublish, override and set a try-on image, but it
-- could not fix a title or file a product under a category — and an affiliate
-- feed supplies neither reliably (four of the five seed products arrived with a
-- null category). Curating a catalog you cannot categorise is not curation.
--
-- Deliberately NOT editable here: price, currency, affiliate_ref, external_id,
-- merchant. Those are claims about the merchant's offer, not editorial fields,
-- and a human typing a price the retailer does not honour is worse than a feed
-- that is briefly stale.
create or replace function public.admin_update_product(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_title text, p_category text, p_subcategory text,
  p_brand text, p_audience text, p_reason text
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

  -- A blank title would leave a product with no name at all; every other field
  -- may legitimately be cleared, so null means "leave" and '' means "clear".
  if p_title is not null and length(btrim(p_title)) = 0 then
    raise exception 'VALIDATION_ERROR: title cannot be blank' using errcode = '22023';
  end if;
  if p_audience is not null and nullif(btrim(p_audience), '') is not null
     and btrim(lower(p_audience)) not in ('women', 'men', 'unisex', 'kids', 'baby') then
    raise exception 'VALIDATION_ERROR: audience %', p_audience using errcode = '22023';
  end if;

  update public.products
     set title       = coalesce(nullif(btrim(p_title), ''), title),
         category    = case when p_category    is null then category
                            else nullif(btrim(p_category), '') end,
         subcategory = case when p_subcategory is null then subcategory
                            else nullif(btrim(p_subcategory), '') end,
         brand       = case when p_brand       is null then brand
                            else nullif(btrim(p_brand), '') end,
         audience    = case when p_audience    is null then audience
                            else nullif(btrim(lower(p_audience)), '') end,
         updated_at  = now()
   where id = p_product_id;

  v_after := admin_product_snapshot(p_product_id);
  return admin_log_audit(p_admin_id, p_admin_email, 'product_update',
           'product', p_product_id::text, p_reason, '{}'::jsonb, v_before, v_after);
end;
$$;

-- ── admin: the fields the console needs to actually curate ─────────────────
-- Four additions, each answering a question the console could not ask:
--   subcategory / audience  — the edit form has to round-trip what it writes.
--   country_eligibility     — whether this row will say "check with retailer".
--   affiliate_host          — HOST ONLY. The full affiliate_ref carries the
--                             tracking parameters that decide who gets paid, so
--                             it is never returned; the host is enough to see
--                             that a link points where it should, and is the
--                             same treatment `admin_list_merchants` gives feed
--                             URLs.
-- The return type changes, so the old signature is dropped first — `create or
-- replace` cannot widen a RETURNS TABLE.
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
  country_eligibility text, affiliate_host text, total_count bigint
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
           public.product_tryon_ready(p) as is_tryon_ready,
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
         count(*) over ()
    from filtered f
   order by f.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- Same contract as every other admin mutation: service_role only, never anon or
-- authenticated. The console holds the service key; a signed-in app user does
-- not become an editor by discovering the function name.
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_update_product(uuid,text,uuid,text,text,text,text,text,text)',
    'admin_list_products(text,uuid,text,text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
