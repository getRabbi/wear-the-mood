-- ============================================================================
-- 0062 — Affiliate network layer: discovered advertisers and their feeds
--
-- ADDITIVE + IDEMPOTENT. Extends the merchant automation from 0057/0061; it
-- does not replace it. `merchant_feed_config` remains the per-merchant SYNC
-- POLICY (enabled, rights, backoff, lock, mapping); what this adds is where a
-- merchant and its feeds came FROM when they were discovered rather than typed.
--
-- WHY A SEPARATE FEED TABLE. 0057 modelled one feed per merchant, because a
-- direct merchant has one. A network advertiser does not: the live Awin account
-- this was built against returns ONE active advertiser with TWENTY-ONE feeds —
-- per category, plus a whole-catalogue feed in another language. Forcing that
-- into a single `feed_url` column would either lose twenty of them or duplicate
-- the merchant twenty-one times, and the second is worse: the same product
-- would exist under twenty-one merchant ids and every save, click and try-on
-- would scatter across them.
--
-- So feeds become rows, and the merchant stays one merchant.
--
-- NO CREDENTIALS ARE STORED HERE. Awin's feed-list response hands back a
-- ready-made download URL with the API key embedded in the PATH. That URL is
-- deliberately never persisted: only the feed's numeric id is kept, and the
-- authenticated URL is rebuilt server-side, per request, from an environment
-- secret. A key in a database column is a key in every backup, every audit
-- snapshot and every admin read that forgets to exclude a column.
-- ============================================================================

-- ── merchants: where this merchant came from ────────────────────────────────

alter table public.merchants
  -- null = created by hand. 'awin' = discovered from a network account.
  add column if not exists network text,
  -- The network's own advertiser id. Not ours, and not a secret.
  add column if not exists network_advertiser_id text,
  -- Non-secret descriptive metadata as the network reported it: region,
  -- vertical, membership status, and when discovery last saw it. Kept as jsonb
  -- because every network describes advertisers differently and inventing a
  -- column per network would mean a migration per network.
  add column if not exists network_metadata jsonb not null default '{}'::jsonb,
  add column if not exists network_last_seen_at timestamptz;

create index if not exists merchants_network_idx
  on public.merchants (network, network_advertiser_id) where network is not null;

-- ── merchant_feeds ──────────────────────────────────────────────────────────
-- One row per (merchant, network feed). Discovered, never typed.

create table if not exists public.merchant_feeds (
  id                 uuid primary key default gen_random_uuid(),
  merchant_id        uuid not null references public.merchants (id) on delete cascade,
  network            text not null default 'awin',

  -- The network's feed identifier. A STRING even though Awin's are numeric,
  -- because the next network's will not be.
  network_feed_id    text not null,
  name               text,
  language           text,
  region             text,
  vertical           text,
  -- What the network claims the feed holds. Advisory only — never used to
  -- decide that a download was complete, because a count from a listing
  -- endpoint is not evidence about the bytes we actually received.
  product_count      integer,
  -- The network's own "last imported"/"last updated" stamp for this feed.
  source_updated_at  timestamptz,

  -- Off by default. Discovering a feed is not deciding to import it.
  enabled            boolean not null default false,

  -- Reconciliation bookkeeping. A feed that disappears from the listing is
  -- marked, never deleted: the products it produced still exist, and a feed
  -- that returns next week should return to the same row.
  last_seen_at       timestamptz,
  removed_at         timestamptz,

  -- Set when a feed needs a human before it can be trusted — an unsupported
  -- format, or a shape the adapter does not recognise. Surfaced in admin as
  -- "needs mapping/review" instead of importing bad products silently.
  needs_review       boolean not null default false,
  review_reason      text,

  raw_metadata       jsonb not null default '{}'::jsonb,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  unique (merchant_id, network, network_feed_id)
);

comment on table public.merchant_feeds is
  'Network-discovered product feeds. One merchant may have many. No credentials: the authenticated URL is rebuilt server-side from env.';

create index if not exists merchant_feeds_enabled_idx
  on public.merchant_feeds (merchant_id, enabled) where enabled and removed_at is null;

-- Service-role only, like every other operator table.
alter table public.merchant_feeds enable row level security;

-- ── merchant_feed_config: network-sourced merchants ─────────────────────────

alter table public.merchant_feed_config
  -- 'url'  = the 0057 behaviour: one feed_url, fetched directly.
  -- 'awin' = feeds come from merchant_feeds and URLs are built server-side.
  add column if not exists source_kind text not null default 'url'
    check (source_kind in ('url', 'awin'));

-- A network merchant has no single feed URL, so the 0057 NOT NULL no longer
-- holds. Dropping a NOT NULL is additive in the sense that matters: every
-- existing row still satisfies the looser constraint.
alter table public.merchant_feed_config alter column feed_url drop not null;

-- ── network_discovery_runs ──────────────────────────────────────────────────
-- Discovery is a job like any other, so it gets run history like any other.

create table if not exists public.network_discovery_runs (
  id                uuid primary key default gen_random_uuid(),
  network           text not null default 'awin',
  status            text not null default 'running',
  trigger_source    text not null default 'cron',
  triggered_by      text,

  advertisers_seen  integer not null default 0,
  advertisers_added integer not null default 0,
  feeds_seen        integer not null default 0,
  feeds_added       integer not null default 0,
  feeds_updated     integer not null default 0,
  feeds_removed     integer not null default 0,

  errors            jsonb not null default '[]'::jsonb,
  error_message     text,
  started_at        timestamptz not null default now(),
  finished_at       timestamptz,
  duration_ms       integer
);

create index if not exists network_discovery_runs_idx
  on public.network_discovery_runs (network, started_at desc);

alter table public.network_discovery_runs enable row level security;

-- ── product_sync_runs: source completeness ──────────────────────────────────
--
-- The single most important column added by this migration.
--
-- Absence reconciliation deactivates products the feed stopped mentioning. That
-- is only sound when the feed was fully read. With a multi-feed merchant and
-- feeds of 150k rows, "we saw fewer products than last time" is at least as
-- likely to mean a timeout, a byte cap or a corrupt gzip as it is to mean the
-- merchant delisted anything.
--
-- So completeness becomes explicit and recorded, and reconciliation is gated on
-- it. A run that could not prove it read everything retires nothing.

alter table public.product_sync_runs
  add column if not exists source_complete boolean not null default true,
  add column if not exists truncated boolean not null default false,
  add column if not exists feeds_completed text[] not null default '{}',
  add column if not exists feeds_failed text[] not null default '{}',
  -- What the source SAID it had, when it says. Recorded for comparison, never
  -- trusted as proof of completeness.
  add column if not exists source_count integer;

comment on column public.product_sync_runs.source_complete is
  'True only when every required feed was fully read. Absence reconciliation runs ONLY when true.';

-- ── flags ───────────────────────────────────────────────────────────────────
-- Discovery has its own switch, separate from product sync: reading a network
-- account is a different risk from importing a catalogue, and turning one off
-- should not require turning the other off.

insert into public.feature_flags (key, enabled, description) values
  ('feature_network_discovery', false,
   'Automation: affiliate network account/feed discovery (Awin)')
on conflict (key) do nothing;
