-- ============================================================================
-- 0002 — Wardrobe background-removal status (CLAUDE.md §2.2, §8)
-- Tracks the async cutout pipeline per item. POST /v1/wardrobe sets 'queued'
-- when an image is supplied; the bg worker claims queued rows, runs background
-- removal, uploads the cutout, and sets cutout_url + status 'done' (or 'failed'
-- — the original image_url keeps displaying either way). NULL = nothing to do.
-- Idempotent: safe to re-run.
-- ============================================================================

alter table public.wardrobe_items
  add column if not exists cutout_status text
    check (cutout_status in ('queued', 'processing', 'done', 'failed', 'skipped'));

-- Partial index so the worker finds pending rows cheaply.
create index if not exists wardrobe_items_cutout_queued_idx
  on public.wardrobe_items (created_at)
  where cutout_status = 'queued';
