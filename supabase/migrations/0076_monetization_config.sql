-- ============================================================================
-- 0076 — Server-authoritative monetization config, experiments, paywall pressure
--
-- ADDITIVE + IDEMPOTENT. Three new tables. No existing table, column, price,
-- allowance, plan, product id or entitlement is read, written or altered by
-- this migration.
--
-- ⚠ THE ONE RULE THIS MIGRATION MUST OBEY (spec §53)
-- --------------------------------------------------
-- The seeded configuration REPRODUCES CURRENT PRODUCTION BEHAVIOUR EXACTLY:
--
--     free lifetime renders  = null  → keep using FREE_TRYON_TRIAL_CREDITS (3)
--     standard render cost   = 1 app credit          (core/plans.STD_COST)
--     HD render cost         = 4 app credits         (core/plans.HD_COST)
--     AI Enhance cost        = 4 app credits         (core/plans.AI_ENHANCE_COST)
--     plans / prices         = read from public.plans, untouched
--     trial                  = disabled
--     rollover               = disabled
--
-- Nothing here changes $8.99, $15.99, 75, 150, `topup_40`, any RevenueCat
-- product id or any entitlement name. This migration makes those values
-- CONFIGURABLE so an experiment can be run deliberately later; it does not run
-- one. A `null` in this table always means "defer to the code default", which
-- is why the safe state is expressible without guessing today's numbers.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── monetization_config ──────────────────────────────────────────────────────
-- Operator-owned, NOT user-owned: no RLS policies, so only the service role can
-- read or write it (the same pattern as ai_usage_log / idempotency_keys). The
-- app never queries it directly — it receives a composed snapshot from
-- GET /v1/monetization/config, which is what keeps the server the authority.
create table if not exists public.monetization_config (
  key         text primary key,
  -- jsonb rather than text so a value can be a number, a boolean, a null or a
  -- structure without a second column per shape. `'null'::jsonb` is the
  -- explicit "use the code default" marker.
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now()
);

comment on table public.monetization_config is
  'Server-authoritative monetization policy. A jsonb null means "defer to the '
  'code default" — which is how the seeded rows reproduce current production '
  'behaviour without restating prices that already live in public.plans.';

alter table public.monetization_config enable row level security;
-- No policies: service-role only, by design.

insert into public.monetization_config (key, value, description) values
  ('free_render_lifetime_limit', 'null'::jsonb,
   'Lifetime free standard renders. null = use FREE_TRYON_TRIAL_CREDITS (current: 3).'),
  ('render_cost_standard', 'null'::jsonb,
   'App credits for a standard render. null = STD_COST (current: 1).'),
  ('render_cost_hd', 'null'::jsonb,
   'App credits for an HD / Try-On Max render. null = HD_COST (current: 4).'),
  ('render_cost_enhance', 'null'::jsonb,
   'App credits for AI Enhance. null = AI_ENHANCE_COST (current: 4).'),
  ('paywall_cooldown_hours', '24'::jsonb,
   'Minimum hours between two INTERRUPTIVE monetization surfaces for one user. '
   'Never applies to a paywall the user opened themselves.'),
  ('paywall_post_purchase_cooldown_hours', '72'::jsonb,
   'Quiet period after any purchase (pack or subscription) before an '
   'interruptive upgrade surface may be shown again.'),
  ('paywall_timing_variant', '"control"'::jsonb,
   'Which moment an interruptive paywall may appear. control = current '
   'behaviour: only where the user asks or runs out.'),
  ('trial_enabled', 'false'::jsonb,
   'Store-level free trial. FALSE = current production behaviour.'),
  ('trial_credit_cap', 'null'::jsonb,
   'Render credits usable during a trial. null = no trial, so no cap.'),
  ('rollover_enabled', 'false'::jsonb,
   'Subscription credit rollover. FALSE = current behaviour (monthly reset, no '
   'rollover). Purchased top-up credits are NEVER subject to rollover rules.'),
  ('rollover_cap_multiplier', '1'::jsonb,
   'Maximum carried-over allowance, as a multiple of one month. Inert while '
   'rollover_enabled is false.'),
  ('quality_recovery_limit_30d', '1'::jsonb,
   'Maximum goodwill re-renders granted per user per 30 days. Bounded on '
   'purpose: "bad result" must never become an unlimited free-render exploit.'),
  ('push_frequency_cap_7d', '2'::jsonb,
   'Maximum non-transactional marketing pushes per user per 7 days. '
   'Transactional messages (render ready, event reminder) are exempt.')
on conflict (key) do nothing;

-- ── experiment_assignments ───────────────────────────────────────────────────
-- Stable, server-side assignment. A payer must never be re-randomized on an app
-- launch (§37), which is exactly what a client-side coin flip would do.
create table if not exists public.experiment_assignments (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  experiment  text not null,
  variant     text not null,
  assigned_at timestamptz not null default now(),
  -- Set the first time the user actually SAW the variant. An assignment with no
  -- exposure is not a data point, and counting it as one biases every result.
  exposed_at  timestamptz,
  primary key (user_id, experiment)
);

comment on table public.experiment_assignments is
  'Server-stable experiment assignment. Written once per (user, experiment) and '
  'never re-rolled; exposure is recorded separately.';

create index if not exists experiment_assignments_experiment_idx
  on public.experiment_assignments (experiment, variant);

alter table public.experiment_assignments enable row level security;

drop policy if exists experiment_assignments_select_own on public.experiment_assignments;
create policy experiment_assignments_select_own on public.experiment_assignments
  for select using (auth.uid() = user_id);
-- No insert/update policy: assignment is a server decision, not a client claim.

-- ── monetization_events ──────────────────────────────────────────────────────
-- The pressure ledger. Every paywall impression, dismissal, CTA and purchase
-- lands here so the cooldown rules are computed from ONE record instead of a
-- scatter of per-widget timestamps that no screen can see (§10).
create table if not exists public.monetization_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  -- Which surface: 'paywall' | 'topup_sheet' | 'render_gate' | 'upgrade_prompt'.
  surface    text not null,
  action     text not null
               check (action in ('viewed', 'dismissed', 'cta_tapped', 'purchased')),
  -- TRUE only when WTM decided to show this, not when the user opened it. Only
  -- interruptive impressions count toward a cooldown — punishing a user for
  -- tapping "Upgrade" themselves would be absurd.
  interruptive boolean not null default false,
  context    jsonb,
  created_at timestamptz not null default now()
);

comment on table public.monetization_events is
  'Central record of monetization surfaces shown and dismissed. The cooldown in '
  '§10 is derived from this, so no two screens can independently spam a user.';

create index if not exists monetization_events_user_created_idx
  on public.monetization_events (user_id, created_at desc);

alter table public.monetization_events enable row level security;

drop policy if exists monetization_events_select_own on public.monetization_events;
create policy monetization_events_select_own on public.monetization_events
  for select using (auth.uid() = user_id);

drop policy if exists monetization_events_insert_own on public.monetization_events;
create policy monetization_events_insert_own on public.monetization_events
  for insert with check (auth.uid() = user_id);

-- ── flags, seeded OFF ────────────────────────────────────────────────────────
-- `feature_monetization_config` gates only whether the app APPLIES the served
-- policy. The endpoint itself is always safe to call: with every value at its
-- seeded default it returns exactly today's numbers.
insert into public.feature_flags (key, enabled, description)
values
  ('feature_render_gate_v2', false,
   'Experimental lifetime free-render allowance. OFF = current free trial.'),
  ('feature_paywall_v2', false,
   'Value-based paywall composition + central pressure limits.'),
  ('feature_credit_economics_v2', false,
   'Quality-proportional credit costs. OFF = legacy 1 standard / 4 HD.'),
  ('feature_credit_rollover_v2', false,
   'Subscription credit rollover. OFF = current monthly reset, no rollover.')
on conflict (key) do nothing;
