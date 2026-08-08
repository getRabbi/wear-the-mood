-- ============================================================================
-- 0058 — News automation: approved sources, item lifecycle, run history
--
-- ADDITIVE + IDEMPOTENT. This does NOT create a second newsroom. The existing
-- ingest path — app/cron/news.py, app.services.news, RssFetcher, the summarizer
-- fallback chain, news_items, the url-unique upsert from 0007 and ai_usage_log
-- — stays exactly where it is. What it lacked was everything an operator needs:
-- a list of sources that can be turned off, a way to tell an unreviewed item
-- from a published one, and any record of what a run did.
--
-- Three additions:
--
--   1. news_sources — the approved list. Feeds move to rows so a source can be
--      disabled at 2am without a deploy, and so "do not blindly auto-publish
--      unknown sources" is enforced by a per-source flag rather than by
--      remembering.
--
--   2. news_items lifecycle — status, source linkage, canonical url,
--      attribution. Existing rows are backfilled to 'published' because they
--      already are: changing what is visible is not this migration's job.
--
--   3. news_sync_runs — per-source run history, so one failing feed is a row
--      rather than a mystery.
--
-- COPYRIGHT: news_items stores a SUMMARY and a link, never article body text.
-- The column that could hold a full copy deliberately does not exist, so the
-- safe thing is also the only representable thing.
-- ============================================================================

-- ── news_sources ────────────────────────────────────────────────────────────

create table if not exists public.news_sources (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique,
  name          text not null,

  -- The feed itself. `rss` is what RssFetcher speaks today; the column exists
  -- so a second kind never needs a schema change.
  feed_url      text not null,
  feed_kind     text not null default 'rss' check (feed_kind in ('rss', 'atom', 'json')),

  -- The publisher's own site, used for attribution display and for deciding
  -- whether a link is on-domain.
  homepage_url  text,
  publisher     text,

  -- Off by default: a source that has been added but not reviewed must not
  -- start ingesting on the next cron tick.
  enabled       boolean not null default false,

  -- Lower runs first. Ordering matters when a daily budget or rate limit means
  -- not every source gets fetched.
  priority      integer not null default 100,

  -- Editorial bucket the items land in.
  category      text,

  -- The trust decision, per source, and the reason this is a column rather
  -- than a global setting. A wire service we have vetted can publish straight
  -- to the feed; anything else lands in REVIEW_REQUIRED for a human. Default
  -- false, so a source added carelessly cannot publish itself.
  auto_publish  boolean not null default false,

  -- Bounded retry, same shape as the product feeds.
  consecutive_failures integer not null default 0,
  retry_after   timestamptz,
  last_run_id   uuid,
  last_success_at timestamptz,
  -- `ok` | `degraded` | `failed`
  health        text not null default 'ok',

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists news_sources_enabled_idx
  on public.news_sources (enabled, priority) where enabled;

-- Read-public is unnecessary — nothing client-side lists sources — so this is
-- default-deny like the other operator tables.
alter table public.news_sources enable row level security;

-- ── news_items: lifecycle + provenance ──────────────────────────────────────

alter table public.news_items
  add column if not exists source_id uuid references public.news_sources (id) on delete set null,

  -- DRAFT | REVIEW_REQUIRED | PUBLISHED | ARCHIVED.
  -- Default 'published' on purpose: every row that exists today is already
  -- being served, and a default of 'draft' would silently empty the live feed
  -- the moment this migration ran. New rows get their status from the
  -- ingester, which uses the source's auto_publish.
  add column if not exists status text not null default 'published'
    check (status in ('draft', 'review_required', 'published', 'archived')),

  -- The de-duplication key. A feed will hand out the same article under
  -- tracking-tagged URLs (utm_*, ?ref=, #fragment) and http vs https, and the
  -- 0007 unique index on `url` cannot see that those are one story. The
  -- ingester normalizes into this column and dedups on it; `url` keeps holding
  -- exactly what the feed said, because that is what a reader should be sent to.
  add column if not exists canonical_url text,

  -- Attribution shown beside the summary. Required by the "no full copyrighted
  -- article copying" rule to be honest about whose reporting this is.
  add column if not exists author text,
  add column if not exists attribution text,

  add column if not exists published_by text,
  add column if not exists published_state_at timestamptz,
  add column if not exists sync_run_id uuid;

-- Backfill: existing rows are live, and their url is already their best
-- canonical key. Both statements are no-ops on re-run.
update public.news_items set status = 'published' where status is null;
update public.news_items
   set canonical_url = url
 where canonical_url is null and url is not null;

-- The real dedup key. Partial + unique: two ingests of one story collapse to a
-- single row no matter which tagged URL each arrived under.
create unique index if not exists news_items_canonical_url_key
  on public.news_items (canonical_url) where canonical_url is not null;

-- The feed reads published items newest-first; this keeps that off the drafts.
create index if not exists news_items_status_published_idx
  on public.news_items (status, published_at desc) where status = 'published';

-- ── news_sync_runs ──────────────────────────────────────────────────────────

create table if not exists public.news_sync_runs (
  id             uuid primary key default gen_random_uuid(),
  -- Nullable: a run that failed before it resolved a source still needs a row.
  source_id      uuid references public.news_sources (id) on delete cascade,

  status         text not null default 'running',
  trigger_source text not null default 'cron',
  triggered_by   text,
  dry_run        boolean not null default false,

  fetched        integer not null default 0,
  created        integer not null default 0,
  updated        integer not null default 0,
  duplicates     integer not null default 0,
  skipped        integer not null default 0,

  errors         jsonb not null default '[]'::jsonb,
  error_message  text,

  started_at     timestamptz not null default now(),
  finished_at    timestamptz,
  duration_ms    integer
);

create index if not exists news_sync_runs_source_idx
  on public.news_sync_runs (source_id, started_at desc);

alter table public.news_sync_runs enable row level security;

-- ── flags ───────────────────────────────────────────────────────────────────

insert into public.feature_flags (key, enabled, description) values
  ('feature_news_automation', false,
   'Automation: newsroom RSS ingestion (cron + admin Sync Now)')
on conflict (key) do nothing;
