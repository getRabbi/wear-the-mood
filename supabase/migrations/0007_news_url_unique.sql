-- ============================================================================
-- 0007 — News dedup (CLAUDE.md §1 pillar 5)
-- The ingestion cron upserts articles by url, so re-runs refresh an item rather
-- than duplicate it. A partial unique index (url where not null) is the dedup
-- key; null urls (rare) are left unconstrained. The table is public-read /
-- service-role-write already (baseline). Idempotent: safe to re-run.
-- ============================================================================

create unique index if not exists news_items_url_key
  on public.news_items (url)
  where url is not null;
