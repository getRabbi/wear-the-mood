-- ============================================================================
-- 0073 — Render cost observability: extend ai_usage_log, record result outcome
--
-- ADDITIVE + IDEMPOTENT. Every column added here is nullable with no default
-- backfill, no existing column changes type or nullability, nothing is dropped
-- and no policy becomes stricter. Deploying it changes nothing observable —
-- the writers start populating the new columns on the next backend release.
--
-- WHY
-- ---
-- `ai_usage_log` already records provider / task / estimated_usd / latency /
-- success for every AI call (§14). What it could NOT answer is the question the
-- retention & monetization work needs answered:
--
--     "How much did this KEPT look actually cost us?"
--
-- Because a row had no job id, no endpoint, no generation mode, no retry counts
-- and no link to whether the user kept or rejected the render. Those are added
-- here rather than in a second ledger, so provider spend keeps exactly ONE
-- durable home and `credit_transactions` keeps its separate one as the
-- financial truth for the user's balance. The two are LINKED (job_id), never
-- merged — a credit is what the user paid, external_units is what we paid.
--
-- Result outcome (kept / rejected) lands on `tryon_results` for the same
-- reason: it is a fact about that result, and putting it there means the cost
-- ledger can join to it instead of duplicating it. A rejection is a STYLE
-- signal, not a refund — the refund path (technical/objective failure) is
-- untouched by this migration.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── ai_usage_log: the provider-economics columns ─────────────────────────────
alter table public.ai_usage_log
  -- The job this call belongs to (tryon_jobs.id / ai_jobs.id). Deliberately NOT
  -- a foreign key: the ledger is an accounting record and must survive the
  -- deletion of the job it describes (a user deleting a result must not erase
  -- what that render cost us).
  add column if not exists job_id uuid,
  -- Provider routing actually used, e.g. 'tryon-v1.6' / 'tryon-max'.
  add column if not exists endpoint text,
  -- Generation mode ('quality' | 'balanced' | 'performance') and output size
  -- ('1k' | '2k' …) as the provider reports them. Free text on purpose: a CHECK
  -- constraint here would turn a provider adding a mode into a 500.
  add column if not exists mode text,
  add column if not exists resolution text,
  -- What the PROVIDER charged, in provider credits (FASHN credits). Kept
  -- alongside estimated_usd so a provider price change re-prices history
  -- instead of corrupting it.
  add column if not exists external_units numeric(10, 3),
  -- What WE charged the user, in app credits, for the action this call served.
  -- The authority is still credit_transactions; this is the denormalized copy
  -- that makes "margin per render" a single-table query.
  add column if not exists wtm_credit_cost integer,
  -- How hard this render was. Transient provider retries vs re-renders forced
  -- by the fidelity gate — two very different cost stories.
  add column if not exists technical_retries integer,
  add column if not exists quality_retries integer,
  -- Terminal state of the quality gate: passed | rejected | unverified | skipped.
  add column if not exists quality_state text,
  -- The plan the user was on when this ran, so COGS can be split by tier
  -- without joining a subscription table that has since changed.
  add column if not exists plan_tier text,
  -- Which experiment arm this render was produced under, when one applies.
  add column if not exists experiment text;

comment on column public.ai_usage_log.job_id is
  'The job this provider call served (tryon_jobs.id / ai_jobs.id). Intentionally '
  'not an FK: the cost record outlives the job it describes.';
comment on column public.ai_usage_log.external_units is
  'Provider-side units consumed (e.g. FASHN credits). estimated_usd is derived '
  'from this at the price in force when the call ran.';
comment on column public.ai_usage_log.wtm_credit_cost is
  'App credits charged for the action. credit_transactions remains the '
  'authority for the user balance; this is the denormalized join-free copy.';

-- Cost questions are always "over a window", usually "for a user" or "for a
-- job". `ai_usage_log_created_idx` already covers the window.
create index if not exists ai_usage_log_job_idx
  on public.ai_usage_log (job_id) where job_id is not null;
create index if not exists ai_usage_log_user_created_idx
  on public.ai_usage_log (user_id, created_at desc);

-- ── tryon_results: did the user keep it? ─────────────────────────────────────
-- Nullable on purpose. NULL means "not answered", which is genuinely different
-- from "rejected" and must never be counted as one.
alter table public.tryon_results
  add column if not exists outcome text,
  add column if not exists rejection_reason text,
  add column if not exists feedback_at timestamptz;

-- Added NOT VALID, then validated separately. A plain `add constraint ... check`
-- holds ACCESS EXCLUSIVE on `tryon_results` for the whole validating scan,
-- which blocks every read and write to try-on history for the duration. NOT
-- VALID takes the lock only long enough to record the constraint, and the
-- follow-up VALIDATE takes SHARE UPDATE EXCLUSIVE — concurrent reads and
-- writes keep working throughout.
--
-- The constraints are trivially satisfied either way: both columns were created
-- NULL two statements ago, and every predicate admits NULL. NOT VALID here is
-- about the LOCK, not about tolerating bad data.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tryon_results_outcome_check') then
    alter table public.tryon_results
      add constraint tryon_results_outcome_check
      check (outcome is null or outcome in ('kept', 'rejected')) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tryon_results_rejection_reason_check') then
    alter table public.tryon_results
      add constraint tryon_results_rejection_reason_check
      check (
        rejection_reason is null or rejection_reason in (
          'identity_issue', 'garment_issue', 'not_my_style',
          'body_proportion_issue', 'color_issue', 'occasion_mismatch', 'other'
        )
      ) not valid;
  end if;
end $$;

alter table public.tryon_results validate constraint tryon_results_outcome_check;
alter table public.tryon_results validate constraint tryon_results_rejection_reason_check;

comment on column public.tryon_results.outcome is
  'User verdict on this render: kept | rejected | null (not answered). A '
  'rejection is a taste signal, NOT a refund trigger — technical and objective '
  'quality failures are refunded upstream by the worker and never reach here.';

create index if not exists tryon_results_outcome_idx
  on public.tryon_results (user_id, outcome) where outcome is not null;

-- ── the question the ledger exists to answer ─────────────────────────────────
-- A read-only view so "cost per kept look" is one query rather than a joined
-- report every caller re-derives. Service-role only, like ai_usage_log itself.
create or replace view public.render_economics as
  select
    u.id                as usage_id,
    u.user_id,
    u.job_id,
    u.provider,
    u.endpoint,
    u.mode,
    u.resolution,
    u.external_units,
    u.estimated_usd,
    u.wtm_credit_cost,
    u.technical_retries,
    u.quality_retries,
    u.quality_state,
    u.plan_tier,
    u.experiment,
    u.latency_ms,
    u.success,
    u.created_at,
    r.id                as result_id,
    r.outcome,
    r.rejection_reason,
    r.feedback_at
  from public.ai_usage_log u
  left join public.tryon_results r on r.job_id = u.job_id
  where u.task in ('tryon', 'enhance_item', 'catalog_model');

comment on view public.render_economics is
  'Provider spend joined to the user verdict for that render. Answers "what did '
  'a kept look cost" without duplicating either ledger. Service-role only.';

-- ⚠ A VIEW DOES NOT INHERIT THE RLS OF ITS BASE TABLES.
--
-- By default a Postgres view executes with the privileges of its OWNER, so the
-- row-level security on `tryon_results` — and the deliberate absence of any
-- policy on the service-role-only `ai_usage_log` — would NOT apply to somebody
-- selecting through this view. Left alone, and with Supabase's default grants
-- on the `public` schema, that would expose every user's render costs and
-- verdicts to any authenticated caller through PostgREST.
--
-- Two independent guards, because either one alone is a single point of
-- failure:
--
--   1. REVOKE the API roles. Works on every Postgres version, and is what
--      actually keeps PostgREST from exposing the view at all.
--   2. `security_invoker` (PG 15+), so that even a future GRANT evaluates the
--      base tables as the CALLER — meaning RLS applies and the view is safe by
--      construction rather than by grant hygiene.
revoke all on public.render_economics from anon, authenticated;

do $$
begin
  -- Guarded: `security_invoker` does not exist before PG 15, and this migration
  -- must not fail on an older instance — the REVOKE above already holds there.
  execute 'alter view public.render_economics set (security_invoker = true)';
exception
  when others then
    raise notice 'security_invoker unsupported; render_economics stays owner-executed (revoked above)';
end $$;
