-- ============================================================================
-- 0045 — recovery lookup indexes for STRANDED `queued` rows
-- ============================================================================
-- 0044 added recovery indexes for stale `processing` rows only, because recovery
-- scanned only that state. That left the other half of the failure model uncovered:
-- a row that committed but whose best-effort wake signal never reached the queue
-- (§11.5) stays `queued` with no message, and the batch workers wake ONLY from queue
-- messages — they never poll the DB for queued rows. Such a row was stranded forever.
--
-- `app.tasks.recovery` now also scans `queued` rows whose signal timestamp is NULL
-- (enqueue failed, or the row predates the queue — e.g. written by the pre-migration
-- DigitalOcean API) or older than WORKER_STALE_SECONDS. These partial indexes keep
-- that scan cheap.
--
-- Idempotent and additive: no data change, no column change, safe to re-run.
-- ============================================================================

create index if not exists tryon_jobs_stranded_idx
  on public.tryon_jobs (last_signal_at) where status = 'queued';

create index if not exists ai_jobs_stranded_idx
  on public.ai_jobs (last_signal_at) where status = 'queued';

create index if not exists wardrobe_items_stranded_idx
  on public.wardrobe_items (cutout_last_signal_at) where cutout_status = 'queued';

-- ============================================================================
-- End of 0045
-- ============================================================================
