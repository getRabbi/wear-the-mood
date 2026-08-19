-- 0072 — canonical news media: provenance, validation state, and a cache policy
-- that is OFF for every publisher.
--
-- ── why ─────────────────────────────────────────────────────────────────────
--
-- `news_items.image_url` was a single unvalidated string: whatever the feed
-- happened to expose, stored without asking whether it loads, whether it is an
-- image, or how big it is. Vogue publishes `media:content`, so Vogue had
-- pictures; Hypebeast hides its image in description HTML and Highsnobiety
-- publishes none at all, so both produced the gradient placeholder — and the
-- only way to know which of "no image", "dead link" or "publisher blocked us"
-- applied was to open the article by hand.
--
-- This adds the smallest contract that makes media state observable, and the
-- one operational switch that keeps us honest about other people's copyright.
--
-- ── rights ──────────────────────────────────────────────────────────────────
--
-- 0065/0067 built an image-rights model for PRODUCTS. It does not extend to
-- news publishers and is not reused here: nothing in it grants Wear The Mood
-- permission to copy a publisher's photograph into R2.
--
-- So `news_sources.media_cache_policy` defaults to 'external_hotlink_only' for
-- EVERY existing and future source. This migration licenses nothing and copies
-- nothing. Moving a source to 'cache_allowed' is a deliberate act, taken after
-- somebody has established the right to do it for that publisher.
--
-- ── safety ──────────────────────────────────────────────────────────────────
--
-- Forward-only, additive, idempotent. Every column is nullable or has a
-- default, so a running instance of the previous release keeps working against
-- this schema during a rolling deploy: it simply does not read the new columns.
-- No column is rewritten, no data is moved, no long lock is taken — `add column
-- ... default` on a non-volatile default does not rewrite the table on
-- PostgreSQL 11+. Backfilling the new columns is the job of a separate,
-- resumable repair command, never of this migration.

-- ── how the hero image was resolved, and whether it works ────────────────────

alter table public.news_items
  -- What the feed/page originally offered, kept even when the resolved URL
  -- differs (a publisher redirect to a CDN). Provenance for the audit trail.
  add column if not exists image_source_url text,
  -- Which convention produced it: rss_media | rss_enclosure | feed_html |
  -- og_image | twitter_image. Answers "which publishers need a page fetch".
  add column if not exists image_provenance text,
  -- ok | missing | unreachable | forbidden | not_an_image | too_small |
  -- invalid_url. `null` means NOT YET RESOLVED — a pre-0072 row — which is
  -- deliberately distinct from `missing` ("we looked; there is nothing").
  add column if not exists image_status text
    check (image_status is null or image_status in (
      'ok', 'missing', 'unreachable', 'forbidden',
      'not_an_image', 'too_small', 'invalid_url'
    )),
  add column if not exists image_width integer,
  add column if not exists image_height integer,
  -- When the resolution above was last proven. Lets the repair skip rows it has
  -- already checked recently, which is what makes it cheap to re-run.
  add column if not exists image_validated_at timestamptz,
  add column if not exists image_status_detail text;

-- The query the image-required Discover/Home placements actually run: newest
-- PUBLISHED stories that have a hero image known to work. Partial, so it stays
-- small and only indexes rows that can be served.
create index if not exists news_items_image_ok_idx
  on public.news_items (coalesce(published_at, created_at) desc)
  where status = 'published' and image_status = 'ok';

-- The repair's own worklist: rows still to be resolved, oldest first.
create index if not exists news_items_image_unresolved_idx
  on public.news_items (created_at)
  where image_status is null;

-- ── per-publisher caching rights: OFF ────────────────────────────────────────

alter table public.news_sources
  add column if not exists media_cache_policy text not null
    default 'external_hotlink_only'
    check (media_cache_policy in ('external_hotlink_only', 'cache_allowed'));

comment on column public.news_sources.media_cache_policy is 'external_hotlink_only (default): reference the publisher''s own URL, never copy the bytes. cache_allowed: this publisher''s imagery may be stored in Wear The Mood storage - set ONLY when the right to do so has been established for that publisher. Product image-rights (0065/0067) do not apply to news media and must not be read as granting this.';

-- Explicitly re-assert the default over any row that predates the column, so
-- "no publisher is cache-allowed" is a fact about the data and not merely about
-- the DDL. Idempotent and a no-op on re-run.
update public.news_sources
   set media_cache_policy = 'external_hotlink_only'
 where media_cache_policy is null;
