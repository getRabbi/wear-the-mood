-- ============================================================================
-- 0046 — dedicated cutout lease column (fixes a recovery livelock)
-- ============================================================================
-- Cutout claims leased on `wardrobe_items.updated_at`. But `updated_at` is
-- maintained by `trg_wardrobe_items_updated_at` -> `set_updated_at()`, which fires
-- on EVERY update of the row — including recovery's own re-signal
-- (`set cutout_last_signal_at = now()`).
--
-- That produced a livelock, caught by the Phase 6 replica-kill preflight:
--   1. a worker claims a row  -> cutout_status='processing', lease stamped
--   2. the execution dies mid-flight, leaving the row 'processing'
--   3. recovery finds it stale and re-signals it
--   4. the re-signal fires the trigger, resetting `updated_at` = the lease clock
--   5. the woken worker can no longer claim it (no longer older than the stale
--      window), deletes the signal as a no-op, and the row stays 'processing'
--   6. repeat forever — the row is re-signalled but NEVER recovered
--
-- `tryon_jobs` / `ai_jobs` never had this bug because they lease on a dedicated
-- `locked_at` column that recovery does not write. This gives cutouts the same
-- shape: `cutout_locked_at` is written ONLY by the claim, never by a re-signal.
--
-- The legacy combined DigitalOcean worker (`app.workers.bg_worker`) keeps using
-- `updated_at` + `requeue_stale` and is deliberately untouched — it remains the
-- rollback path and the two planes never run concurrently.
--
-- Additive and idempotent: new nullable column + backfill + partial index.
-- ============================================================================

alter table public.wardrobe_items
  add column if not exists cutout_locked_at timestamptz;

-- Backfill in-flight rows so nothing is treated as "never leased" (NULL) right
-- after deploy. NULL is claimable by design (that is how Azure adopts a row the
-- stopped DO worker abandoned at cutover), but existing rows should keep their
-- real lease age rather than becoming instantly claimable.
update public.wardrobe_items
   set cutout_locked_at = updated_at
 where cutout_status = 'processing'
   and cutout_locked_at is null;

-- Recovery lookup: find stale in-flight cutouts cheaply.
create index if not exists wardrobe_items_cutout_lease_idx
  on public.wardrobe_items (cutout_locked_at) where cutout_status = 'processing';

-- ============================================================================
-- End of 0046
-- ============================================================================
