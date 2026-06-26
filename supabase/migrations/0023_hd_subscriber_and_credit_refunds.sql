-- ============================================================================
-- 0023 — HD for Pro + Pro Max, and credit-transaction bucket split for refunds
-- (PART 1 — HD credit enforcement + reserve-at-submit / refund-on-fail)
--
--   * plans.hd_allowed = true for BOTH 'pro' and 'pro_max' — HD / Try-On Max is a
--     SUBSCRIBER feature (Pro OR Pro Max) and still costs 4 credits. Free users
--     stay locked (HD_LOCKED) even if they hold top-up credits.
--   * credit_transactions.meta — records the per-bucket split of a spend
--     (free / plan / topup) so a refund reverses the EXACT buckets that were
--     debited, making a refund perfectly neutral (no free→paid laundering).
--
-- Additive, idempotent, re-runnable. Touches NOTHING in the free 2D path.
-- ============================================================================

-- HD is now a subscriber feature for both paid tiers (Pro Max was already true).
update public.plans
   set hd_allowed = true, updated_at = now()
 where tier in ('pro', 'pro_max');

-- Per-bucket split of each ledger row, so refund_credit() can reverse the exact
-- buckets a spend drew from. Defaults to '{}' for existing rows (never refunded).
alter table public.credit_transactions
  add column if not exists meta jsonb not null default '{}'::jsonb;
