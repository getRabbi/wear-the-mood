-- ============================================================================
-- 0044 — Job reliability fields for the Azure queue + recovery architecture
-- (Wear The Mood infra migration, blueprint §11.3)
--
-- Adds the minimal columns/constraints the split workers + recovery task need:
--   * attempt_count   — authoritative attempt counter (DB owns it, not the queue §4.4)
--   * locked_at       — claim/lease start; recovery re-signals rows stale past
--                       WORKER_STALE_SECONDS still in 'processing'
--   * last_signal_at  — last wake-signal timestamp (best-effort enqueue §11.5)
--   * error_code      — non-secret error category (§11.3)
--   * output uniqueness — one final result/generated row per job, so a duplicate
--                         wake signal or a re-processed job can NEVER double-write
--                         the output ledger (§11.3). Credit spend/refund idempotency
--                         is already enforced by credit_transactions.unique(user_id, ref).
--
-- ADDITIVE + DEFAULTED + IDEMPOTENT + re-runnable. Old DigitalOcean combined-worker
-- code ignores these columns and is unaffected. Applied to the NEW us-east-1 project
-- in Phase 3 (NOT to the Tokyo prod DB in Phase 2). Do NOT touch FASHIONOS_BASELINE.sql.
-- ============================================================================

-- ── tryon_jobs / ai_jobs — attempt/lease/signal/error ───────────────────────
alter table public.tryon_jobs
  add column if not exists attempt_count  integer not null default 0,
  add column if not exists locked_at      timestamptz,
  add column if not exists last_signal_at timestamptz,
  add column if not exists error_code     text;

alter table public.ai_jobs
  add column if not exists attempt_count  integer not null default 0,
  add column if not exists locked_at      timestamptz,
  add column if not exists last_signal_at timestamptz,
  add column if not exists error_code     text;

-- wardrobe_items already has updated_at (used as the cutout lease today); add the
-- attempt counter + a signal timestamp + a non-secret cutout error category.
alter table public.wardrobe_items
  add column if not exists attempt_count         integer not null default 0,
  add column if not exists cutout_last_signal_at timestamptz,
  add column if not exists cutout_error_code     text;

-- ── recovery lookup indexes — find stale non-terminal rows cheaply ──────────
create index if not exists tryon_jobs_recovery_idx
  on public.tryon_jobs (locked_at) where status = 'processing';
create index if not exists ai_jobs_recovery_idx
  on public.ai_jobs (locked_at) where status = 'processing';
create index if not exists wardrobe_items_recovery_idx
  on public.wardrobe_items (updated_at) where cutout_status = 'processing';

-- ── output uniqueness — one terminal output row per job ─────────────────────
-- tryon_results.job_id is NOT NULL → plain unique. generated_images.job_id is
-- nullable (ai_job delete sets it null) → partial unique on non-null job_id, so
-- historical rows whose job was deleted keep coexisting.
create unique index if not exists tryon_results_job_uidx
  on public.tryon_results (job_id);
create unique index if not exists generated_images_job_uidx
  on public.generated_images (job_id) where job_id is not null;

-- ============================================================================
-- End of 0044
-- ============================================================================
