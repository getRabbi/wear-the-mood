-- ============================================================================
-- 0053 — Discover shopping catalog: merchants, products, variants
--        (DISCOVER spec §17.1–17.3, §34, §35)
--
-- ADDITIVE + IDEMPOTENT. Creates three new tables and touches nothing that
-- exists. Every Discover feature that reads them is behind a feature flag that
-- is OFF, so applying this migration changes no user-visible behaviour; it only
-- makes the tables available to seed.
--
-- MONEY IS INTEGER MINOR UNITS + AN ISO CURRENCY CODE. Never a float: binary
-- floating point cannot represent most decimal prices exactly, and a catalog
-- that drifts by a cent per sync eventually shows a price the retailer does not
-- honour. `price_minor` is "the smallest unit of `currency`" — cents for USD,
-- poisha for BDT, and yen for JPY where the minor unit IS the major one. No FX
-- conversion anywhere: a product is priced in one currency and displayed in it.
--
-- RLS: products and merchants are read-public, but ONLY rows that are safe to
-- show — active, approved, in-window, with rights cleared and a fresh sync.
-- The suppression rules live in the POLICY rather than only in the API so a
-- stale or unlicensed row cannot leak through a future endpoint that forgets
-- to filter (§35). All writes are service-role (curation/import, §17 security).
-- ============================================================================

-- ── merchants ───────────────────────────────────────────────────────────────

create table if not exists public.merchants (
  id                  uuid primary key default gen_random_uuid(),
  name                text not null,
  slug                text not null unique,
  logo_url            text,
  -- Which affiliate network the merchant is reached through. The network's
  -- credentials and tracking template are BACKEND-ONLY config and are
  -- deliberately not modelled here — nothing confidential belongs in a
  -- read-public table (§17 security, §38).
  affiliate_network   text,
  -- Domains this merchant is allowed to redirect to. Phase 4's redirect
  -- validates against this allow-list server-side; an empty array means the
  -- merchant cannot be redirected to at all (§38).
  allowed_domains     text[] not null default '{}',
  -- ISO-3166-1 alpha-2, uppercase. `supported_countries` is where the merchant
  -- sells; `shipping_countries` is where it will actually deliver. They differ
  -- more often than not, and ranking must use the shipping list (§34).
  supported_countries text[] not null default '{}',
  shipping_countries  text[] not null default '{}',
  approved            boolean not null default false,
  -- Rolling health of the merchant's product feed, maintained by the importer.
  -- `ok` | `degraded` | `stale` | `failed`.
  feed_health         text not null default 'ok',
  last_synced_at      timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists merchants_approved_idx
  on public.merchants (approved) where approved;

alter table public.merchants enable row level security;

drop policy if exists merchants_select_approved on public.merchants;
-- Only approved merchants are visible. An unapproved merchant is a draft.
create policy merchants_select_approved on public.merchants
  for select using (approved);

-- ── products ────────────────────────────────────────────────────────────────

create table if not exists public.products (
  id                    uuid primary key default gen_random_uuid(),
  merchant_id           uuid not null references public.merchants (id) on delete cascade,
  -- The merchant's own id for this product. Unique per merchant so a re-import
  -- updates rather than duplicates.
  external_id           text not null,

  title                 text not null,
  description           text,
  brand                 text,
  category              text,
  subcategory           text,
  -- women | men | unisex | kids | baby — matches the app's rollout categories.
  audience              text,
  colors                text[] not null default '{}',
  sizes                 text[] not null default '{}',

  -- Money: integer minor units + ISO-4217. See the header.
  price_minor           bigint not null check (price_minor >= 0),
  original_price_minor  bigint check (original_price_minor >= 0),
  currency              char(3) not null,

  image_urls            text[] not null default '{}',
  -- Where to centre a portrait crop, 0..1 in each axis, so a face or a hemline
  -- is not cut off by the story/card aspect ratio (§6.2, §27).
  image_focal_x         real not null default 0.5 check (image_focal_x between 0 and 1),
  image_focal_y         real not null default 0.5 check (image_focal_y between 0 and 1),

  -- An OPAQUE reference the redirect service resolves into a real destination.
  -- The raw affiliate URL and its tracking parameters never reach the client
  -- (§18, §38, safety rule 11).
  affiliate_ref         text not null,

  country_availability  text[] not null default '{}',
  -- in_stock | low_stock | out_of_stock | unknown
  stock_status          text not null default 'unknown',
  -- unsupported | pending | ready. A product is only ever LABELLED Try-On Ready
  -- once compatibility has actually passed (§35) — `pending` is not ready.
  try_on_status         text not null default 'unsupported',
  -- unknown | licensed | restricted. `unknown` and `restricted` are suppressed:
  -- we show product imagery only where the rights are recorded (§35).
  image_rights_status   text not null default 'unknown',
  source_terms_ref      text,

  active                boolean not null default true,
  -- Optional scheduling window; null means always.
  starts_at             timestamptz,
  ends_at               timestamptz,
  -- When the importer last confirmed price and stock. A row that has not been
  -- confirmed recently is suppressed rather than shown with a claim we can no
  -- longer stand behind (§35 "price/stock sync failure must not silently
  -- display indefinite old claims").
  last_synced_at        timestamptz not null default now(),
  -- Sponsored placements must be labelled and tracked separately, never
  -- disguised as an organic match (§39).
  sponsored             boolean not null default false,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  unique (merchant_id, external_id)
);

-- How long a product may go unconfirmed before it is suppressed. A function
-- rather than a literal so the threshold is changed in one place, and so the
-- RLS policy and the API cannot drift apart.
create or replace function public.product_staleness_limit()
returns interval language sql immutable as $$ select interval '7 days' $$;

-- The single definition of "safe to show". Used by the RLS policy AND by the
-- API, so a product suppressed for one is suppressed for both.
create or replace function public.product_is_servable(p public.products)
returns boolean language sql stable as $$
  select p.active
     and coalesce(p.starts_at, '-infinity'::timestamptz) <= now()
     and coalesce(p.ends_at, 'infinity'::timestamptz) > now()
     and p.stock_status <> 'out_of_stock'
     and p.image_rights_status = 'licensed'
     and array_length(p.image_urls, 1) >= 1
     and p.last_synced_at > now() - public.product_staleness_limit()
$$;

create index if not exists products_servable_idx
  on public.products (merchant_id, created_at desc)
  where active;
create index if not exists products_country_idx
  on public.products using gin (country_availability);
create index if not exists products_category_idx
  on public.products (category, subcategory);
-- Keyset pagination orders by (created_at, id) so a stable cursor exists and
-- pages cannot drift or duplicate as rows are inserted (§23, §37.2).
create index if not exists products_keyset_idx
  on public.products (created_at desc, id desc);

alter table public.products enable row level security;

drop policy if exists products_select_servable on public.products;
create policy products_select_servable on public.products
  for select using (
    public.product_is_servable(products)
    and exists (
      select 1 from public.merchants m
       where m.id = products.merchant_id and m.approved
    )
  );

-- ── product_variants ────────────────────────────────────────────────────────
-- Size/colour combinations, because "this product has size M" and "size M is in
-- stock in black" are different claims and only the second one is safe to act
-- on (§12.16, §17.3).

create table if not exists public.product_variants (
  id                    uuid primary key default gen_random_uuid(),
  product_id            uuid not null references public.products (id) on delete cascade,
  external_variant_id   text not null,
  color                 text,
  size                  text,
  -- Null means "same as the parent product" rather than free.
  price_minor           bigint check (price_minor >= 0),
  original_price_minor  bigint check (original_price_minor >= 0),
  stock_status          text not null default 'unknown',
  available             boolean not null default true,
  updated_at            timestamptz not null default now(),

  unique (product_id, external_variant_id)
);

create index if not exists product_variants_product_idx
  on public.product_variants (product_id) where available;

alter table public.product_variants enable row level security;

drop policy if exists product_variants_select_servable on public.product_variants;
-- A variant is visible only when its parent product is.
create policy product_variants_select_servable on public.product_variants
  for select using (
    exists (
      select 1 from public.products p
       where p.id = product_variants.product_id
         and public.product_is_servable(p)
         and exists (
           select 1 from public.merchants m
            where m.id = p.merchant_id and m.approved
         )
    )
  );

-- ── feature flags ───────────────────────────────────────────────────────────
-- Registered so ops can SEE them in the flags table and flip them per
-- environment. Every one is inserted FALSE: Discover is enabled by staged
-- remote rollout, never by a migration turning it on in production.

insert into public.feature_flags (key, enabled, description) values
  ('feature_discover', false, 'Discover: the Discover tab (replaces the Social tab label)'),
  ('feature_discover_stories', false, 'Discover: the Stories rail and viewer'),
  ('feature_shopping', false, 'Discover: affiliate product catalog, feed and product details'),
  ('feature_community_posting', false, 'Community: public create-post entry points'),
  ('feature_community_notifications', false, 'Community: discovery/activity notifications'),
  ('feature_legacy_home_discover', false, 'Home: the legacy Giveaways/Offers/Newsroom shortcut row')
on conflict (key) do nothing;
