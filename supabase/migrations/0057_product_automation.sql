-- ============================================================================
-- 0057 — Product automation: merchant feed config, sync runs, sync bookkeeping
--
-- ADDITIVE + IDEMPOTENT. Builds the ingestion layer ON TOP of the catalog that
-- 0053 already created. It does NOT redefine merchants, products,
-- product_variants or product_is_servable() — those stay exactly as they are,
-- and every suppression rule the RLS policy already enforces keeps working
-- unchanged.
--
-- Three things are added:
--
--   1. merchant_feed_config — WHERE a merchant's products come from. Separate
--      from `merchants` because merchants is READ-PUBLIC by RLS: a feed URL can
--      carry an API key in its query string, so it belongs in a default-deny
--      table like merchant_affiliate_config, never beside the merchant's name.
--
--   2. product_sync_runs — one row per attempt, with counts and errors. Without
--      run history "the catalog looks wrong" has no answer; with it, every
--      product's last change is attributable to a run.
--
--   3. Bookkeeping columns on products — enough to tell "the feed stopped
--      mentioning this" from "a human turned this off", which is the difference
--      between a safe deactivation and destroying somebody's curation.
--
-- Nothing here turns anything on. `feature_product_automation` is inserted
-- FALSE, and the cron refuses to run without it.
-- ============================================================================

-- ── merchant_feed_config ────────────────────────────────────────────────────
-- One feed per merchant. A merchant with no row here is simply not synced,
-- which is how "approved/configured sources only" is enforced structurally
-- rather than by remembering to filter.

create table if not exists public.merchant_feed_config (
  merchant_id      uuid primary key references public.merchants (id) on delete cascade,

  -- Where the product feed lives and how to read it. `format` is a code the
  -- importer dispatches on, so adding a network never changes this schema.
  -- `json` | `csv` | `xml`.
  feed_url         text not null,
  feed_format      text not null default 'json',

  -- Off by default. A configured feed that nobody has reviewed must not start
  -- importing merely because the row exists.
  enabled          boolean not null default false,

  -- How often this feed may be pulled. The runner treats it as a floor, not a
  -- schedule: a manual "Sync Now" bypasses it, an automatic run respects it.
  min_interval_minutes integer not null default 360
    check (min_interval_minutes between 5 and 10080),

  -- Consecutive failures, and when to next allow an automatic attempt. This is
  -- the backoff state: a feed that is down must not be retried every cron tick
  -- for a day, because a hammered endpoint is how an API key gets revoked.
  consecutive_failures integer not null default 0,
  retry_after      timestamptz,

  -- The per-source LOCK. Two overlapping runs against one feed would race on
  -- the same external_ids and could deactivate rows the other just wrote.
  -- Claimed with a timestamp rather than a boolean so a crashed run's lock
  -- expires instead of wedging the feed forever.
  locked_at        timestamptz,
  locked_by        text,

  -- Import policy, per merchant. Some feeds are trustworthy about rights and
  -- some are not, and that is not a global decision.
  -- `licensed` means the merchant's agreement covers the imagery it serves;
  -- anything else and imported products land with image_rights_status
  -- 'unknown', which product_is_servable() already suppresses.
  image_rights_default text not null default 'unknown'
    check (image_rights_default in ('unknown', 'licensed', 'restricted')),

  -- How many consecutive runs a product may be absent before it is deactivated.
  -- Not zero: feeds truncate, paginate badly and time out, and one bad fetch
  -- must not empty a merchant's catalog.
  missing_runs_before_deactivate integer not null default 2
    check (missing_runs_before_deactivate between 1 and 10),

  last_run_id      uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

comment on table public.merchant_feed_config is
  'Per-merchant product feed source + import policy. Service-role only: a feed URL may embed a credential.';

-- RLS on, deliberately no policies: default-deny, exactly like
-- merchant_affiliate_config. Nothing client-side ever reads a feed URL.
alter table public.merchant_feed_config enable row level security;

-- ── product_sync_runs ───────────────────────────────────────────────────────
-- One row per attempt, successful or not.

create table if not exists public.product_sync_runs (
  id             uuid primary key default gen_random_uuid(),
  merchant_id    uuid not null references public.merchants (id) on delete cascade,

  -- `running` | `success` | `partial` | `failed` | `skipped`
  status         text not null default 'running',

  -- What started it, for the audit trail: `cron` | `admin` | `cli`.
  trigger_source text not null default 'cron',
  triggered_by   text,

  -- A dry run reads the feed and computes every decision, then writes nothing
  -- but this row. It is how a feed is validated before it is trusted.
  dry_run        boolean not null default false,

  fetched        integer not null default 0,
  created        integer not null default 0,
  updated        integer not null default 0,
  unchanged      integer not null default 0,
  deactivated    integer not null default 0,
  reactivated    integer not null default 0,
  skipped        integer not null default 0,

  -- Bounded: a feed that fails on every row must not write a megabyte of
  -- near-identical errors into a table somebody has to read.
  errors         jsonb not null default '[]'::jsonb,
  error_message  text,

  started_at     timestamptz not null default now(),
  finished_at    timestamptz,
  duration_ms    integer
);

create index if not exists product_sync_runs_merchant_idx
  on public.product_sync_runs (merchant_id, started_at desc);
create index if not exists product_sync_runs_status_idx
  on public.product_sync_runs (status, started_at desc);

alter table public.product_sync_runs enable row level security;

-- ── products: sync bookkeeping ──────────────────────────────────────────────
-- Additive columns only. Existing rows get defaults that mean "never synced by
-- the importer", which is true of everything seeded or curated by hand.

alter table public.products
  add column if not exists source_run_id uuid,
  -- Hash of the normalized payload the feed last supplied. The whole point of
  -- "unchanged products do not churn": if the hash matches, the row is left
  -- alone, so updated_at and last_synced_at stay meaningful and the feed cannot
  -- make every product look freshly changed on every run.
  add column if not exists source_hash text,
  add column if not exists last_seen_in_feed_at timestamptz,
  -- How many consecutive runs this product has been absent from its feed.
  add column if not exists missing_run_count integer not null default 0,
  -- Set when the importer deactivates a product for absence, so a later run can
  -- tell "the importer retired this" from "an admin unpublished this" and
  -- restore only the former.
  add column if not exists deactivated_by_sync_at timestamptz,

  -- MANUAL OVERRIDE. The importer must never silently undo a human decision.
  -- Each flag freezes one aspect of the row against feed updates.
  add column if not exists manual_override boolean not null default false,
  -- Which fields a human has taken ownership of, e.g. ['title','image_urls'].
  -- Empty with manual_override true means the WHOLE row is frozen.
  add column if not exists manual_override_fields text[] not null default '{}',
  add column if not exists manual_override_by text,
  add column if not exists manual_override_at timestamptz,

  -- The admin-chosen try-on garment image. When set it wins over image_urls[1]
  -- for try-on, and the importer never overwrites it. This is the "preferred
  -- Try-On image" the app's Product.tryOnGarmentImageUrl will read once it is
  -- served; until then it is inert data, which is why adding it is safe.
  add column if not exists tryon_image_url text,
  add column if not exists tryon_image_source text
    check (tryon_image_source is null or tryon_image_source in ('feed', 'admin', 'derived'));

create index if not exists products_sync_bookkeeping_idx
  on public.products (merchant_id, last_seen_in_feed_at);
-- Partial: the importer's "what did I not see this run" scan only ever looks at
-- live rows, and this keeps that scan off the retired ones.
create index if not exists products_active_external_idx
  on public.products (merchant_id, external_id) where active;

-- ── flags ───────────────────────────────────────────────────────────────────
-- Registered OFF. Automation is enabled by a deliberate flip in the admin
-- console, never by a migration running in production.

insert into public.feature_flags (key, enabled, description) values
  ('feature_product_automation', false,
   'Automation: merchant product feed ingestion (cron + admin Sync Now)')
on conflict (key) do nothing;
