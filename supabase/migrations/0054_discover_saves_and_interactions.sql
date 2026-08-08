-- ============================================================================
-- 0054 — Discover saves, interactions and shopping preferences
--        (DISCOVER spec §17.5–17.6, §19.3–19.4, §36, §37.3)
--
-- ADDITIVE + IDEMPOTENT. Own-row RLS on everything here: this is per-user
-- behaviour, and none of it is readable by anyone else.
--
-- Every write is IDEMPOTENT BY CONSTRUCTION rather than by hoping the client
-- only sends once (§37.3). A save is a primary key on (user_id, product_id), so
-- a double-tap or a retried request is the same row. An interaction carries a
-- client-generated event id, unique per user, so a retry after a dropped
-- response cannot inflate the behavioural signal that ranking reads from.
-- ============================================================================

-- ── saved_products ──────────────────────────────────────────────────────────

create table if not exists public.saved_products (
  user_id                    uuid not null references public.profiles (id) on delete cascade,
  product_id                 uuid not null references public.products (id) on delete cascade,
  saved_at                   timestamptz not null default now(),
  price_alert_enabled        boolean not null default true,
  availability_alert_enabled boolean not null default false,
  -- The price when it was saved, so a later drop can be detected without
  -- keeping a separate price history. Minor units + ISO code, like everywhere.
  saved_price_minor          bigint,
  saved_currency             char(3),

  primary key (user_id, product_id)
);

create index if not exists saved_products_user_idx
  on public.saved_products (user_id, saved_at desc);

alter table public.saved_products enable row level security;

drop policy if exists saved_products_select_own on public.saved_products;
create policy saved_products_select_own on public.saved_products
  for select using (auth.uid() = user_id);

drop policy if exists saved_products_insert_own on public.saved_products;
create policy saved_products_insert_own on public.saved_products
  for insert with check (auth.uid() = user_id);

drop policy if exists saved_products_update_own on public.saved_products;
create policy saved_products_update_own on public.saved_products
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists saved_products_delete_own on public.saved_products;
create policy saved_products_delete_own on public.saved_products
  for delete using (auth.uid() = user_id);

-- ── product_interactions ────────────────────────────────────────────────────
-- The behavioural signal ranking reads (§19.3/§19.4). Positive and negative
-- alike: a "not my style" is as useful as a save, and more actionable.

create table if not exists public.product_interactions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  product_id      uuid references public.products (id) on delete cascade,
  merchant_id     uuid references public.merchants (id) on delete cascade,

  -- impression | open | save | unsave | try_on | add_to_look | shop_click
  -- | not_my_style | too_expensive | wrong_size | wrong_category
  -- | hide_product | hide_merchant | report_info
  event_type      text not null,

  -- Where in Discover it happened: story_rail | feed_grid | complete_look
  -- | search | saved | product_details. A typed code, never display text.
  feed_placement  text,
  story_id        text,
  tracking_token  text,
  -- Deliberately not a free-form blob of whatever the client felt like
  -- sending; the backend writes only known keys into it.
  metadata        jsonb not null default '{}'::jsonb,

  -- Client-generated, stable across retries of the SAME user action. The
  -- unique index below is what makes a retry a no-op instead of a second
  -- signal (§37.3, §17 "add idempotency/uniqueness protection").
  client_event_id text,

  created_at      timestamptz not null default now()
);

create unique index if not exists product_interactions_dedupe_idx
  on public.product_interactions (user_id, client_event_id)
  where client_event_id is not null;

create index if not exists product_interactions_user_idx
  on public.product_interactions (user_id, created_at desc);
create index if not exists product_interactions_product_idx
  on public.product_interactions (product_id, event_type);

alter table public.product_interactions enable row level security;

drop policy if exists product_interactions_select_own on public.product_interactions;
create policy product_interactions_select_own on public.product_interactions
  for select using (auth.uid() = user_id);

drop policy if exists product_interactions_insert_own on public.product_interactions;
create policy product_interactions_insert_own on public.product_interactions
  for insert with check (auth.uid() = user_id);

-- ── shopping_preferences ────────────────────────────────────────────────────
-- The user-controlled inputs to personalization (§19.5 cold start, §36 privacy).
-- A missing row means all-defaults, so provisioning stays lazy — nothing has to
-- back-fill a row for every existing user.

create table if not exists public.shopping_preferences (
  user_id             uuid primary key references public.profiles (id) on delete cascade,
  -- Where the user shops. Resolved from account/preferences, NEVER from
  -- precise location (§34, §36).
  country             char(2),
  currency            char(3),
  -- Minor units, like every other price in this schema.
  budget_min_minor    bigint check (budget_min_minor >= 0),
  budget_max_minor    bigint check (budget_max_minor >= 0),
  sizes               text[] not null default '{}',
  favorite_categories text[] not null default '{}',
  avoided_colors      text[] not null default '{}',
  modest_preference   boolean not null default false,
  -- Lets a user turn off behavioural personalization while still using
  -- Discover — a required control (§36).
  personalization_enabled boolean not null default true,
  hidden_merchant_ids uuid[] not null default '{}',
  updated_at          timestamptz not null default now(),

  check (
    budget_min_minor is null
    or budget_max_minor is null
    or budget_min_minor <= budget_max_minor
  )
);

alter table public.shopping_preferences enable row level security;

drop policy if exists shopping_preferences_select_own on public.shopping_preferences;
create policy shopping_preferences_select_own on public.shopping_preferences
  for select using (auth.uid() = user_id);

drop policy if exists shopping_preferences_upsert_own on public.shopping_preferences;
create policy shopping_preferences_upsert_own on public.shopping_preferences
  for insert with check (auth.uid() = user_id);

drop policy if exists shopping_preferences_update_own on public.shopping_preferences;
create policy shopping_preferences_update_own on public.shopping_preferences
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
