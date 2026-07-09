-- ============================================================================
-- 0036 — Credits RLS lockdown + HD / Try-On Max = Pro Max only
-- (security fix + founder decision, 2026-07-02)
--
--   PART 1 — SECURITY (critical): public.credits was CLIENT-WRITABLE via the
--     baseline `credits_rw_own` (FOR ALL) policy. An authenticated user could
--     `update public.credits set balance = 999999 …` straight through PostgREST
--     (their JWT satisfies auth.uid() = user_id), granting themselves unlimited
--     credits and resetting their free trial — bypassing the server credit
--     authority entirely. Replace it with a SELECT-only policy. Every credit
--     mutation already runs as the table owner (service role) and BYPASSES RLS,
--     so the server keeps working unchanged.
--
--   PART 2 — HD gating: HD / Try-On Max is Pro Max ONLY (reverts 0023, which had
--     made HD a Pro-OR-Pro-Max feature). Pro drops back to hd_allowed=false;
--     Pro Max stays true. Standard generation (1 credit) is unchanged for both
--     paid tiers. Cost unchanged (HD = 4 credits). Free users stay locked.
--
-- Additive, idempotent, re-runnable. Touches NOTHING in the free 2D path and no
-- pricing beyond HD eligibility.
-- ============================================================================

-- ── PART 1 — credits RLS lockdown ───────────────────────────────────────────
alter table public.credits enable row level security;        -- no-op if already on

-- Drop the dangerous client-writable policy (baseline `credits_rw_own`, FOR ALL).
drop policy if exists credits_rw_own on public.credits;
-- Re-create idempotently: authenticated users may READ their own row only.
drop policy if exists credits_select_own on public.credits;
create policy credits_select_own on public.credits
  for select
  using (auth.uid() = user_id);
-- No INSERT / UPDATE / DELETE policy exists for public.credits → an authenticated
-- client can never write/grant credits. The backend writes as the table owner
-- (service role), which bypasses RLS.

-- Defense-in-depth: also revoke direct write privileges from the client roles, so
-- a client cannot mutate credits even if a permissive policy is ever re-added by
-- mistake. SELECT is retained so the read policy above works. Guarded so it is a
-- no-op on a DB that doesn't have the Supabase client roles.
do $$
begin
  revoke insert, update, delete on public.credits from authenticated;
exception when undefined_object then null;
end $$;
do $$
begin
  revoke insert, update, delete on public.credits from anon;
exception when undefined_object then null;
end $$;

-- ── PART 2 — HD / Try-On Max = Pro Max only ─────────────────────────────────
update public.plans set hd_allowed = false, updated_at = now() where tier = 'pro';
update public.plans set hd_allowed = true,  updated_at = now() where tier = 'pro_max';
