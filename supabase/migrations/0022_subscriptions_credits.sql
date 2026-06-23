-- ============================================================================
-- 0022 — Subscriptions + AI credits (Pro / Pro Max + top-ups) — monetization
-- (CLAUDE.md §18, §25; BUILD_PROMPT_PRO_PROMAX Phase 2 · subsystem 1)
--
-- Data model for the METERED AI-credit subscription system:
--   * plans               — config source of truth (price, monthly_credits, hd_allowed)
--   * user_subscriptions  — per-user tier + billing period (authority for tier)
--   * credit_transactions — immutable ledger / audit trail (idempotent via ref)
--   * top_up_purchases    — one-off credit-pack purchases (idempotent via store_txn_id)
--   * credits.topup_balance — paid top-up credits that SURVIVE the monthly reset
--   * tryon_jobs.hd       — marks an HD / Try-On Max render (4 credits) for the worker
--   * app_grant_credits() — the ONE idempotent grant primitive (webhook/cron/migration)
--
-- Server is the ONLY authority: a user may READ their own balance/tier; EVERY
-- credit mutation is service-role only (no write RLS). Credits are read from
-- plans.monthly_credits (config), never hardcoded. Idempotent + re-runnable.
-- Touches NOTHING in the 2D try-on path.
-- ============================================================================

-- ── plans (config source of truth) ─────────────────────────────────────────
create table if not exists public.plans (
  tier            text primary key,                  -- free | pro | pro_max | topup_40
  kind            text not null default 'subscription'
                    check (kind in ('subscription', 'topup')),
  price_usd       numeric(8, 2) not null default 0,
  monthly_credits integer not null default 0,        -- CONFIG allowance (75 / 150 / 40…)
  hd_allowed      boolean not null default false,    -- HD / Try-On Max permitted
  priority        boolean not null default false,
  play_product_id text,                              -- Google Play SKU (maps webhook→tier)
  app_product_id  text,                              -- App Store SKU
  active          boolean not null default true,
  updated_at      timestamptz not null default now()
);

insert into public.plans
  (tier, kind, price_usd, monthly_credits, hd_allowed, priority, play_product_id, app_product_id)
values
  ('free',     'subscription',  0.00,   0, false, false, null,              null),
  ('pro',      'subscription',  8.99,  75, false, false, 'pro_monthly',     'pro_monthly'),
  ('pro_max',  'subscription', 15.99, 150, true,  true,  'pro_max_monthly', 'pro_max_monthly'),
  ('topup_40', 'topup',         4.99,  40, false, false, 'topup_40',        'topup_40')
on conflict (tier) do update set
  kind            = excluded.kind,
  price_usd       = excluded.price_usd,
  monthly_credits = excluded.monthly_credits,
  hd_allowed      = excluded.hd_allowed,
  priority        = excluded.priority,
  play_product_id = excluded.play_product_id,
  app_product_id  = excluded.app_product_id,
  active          = excluded.active,
  updated_at      = now();

-- ── user_subscriptions (authority for tier + billing period) ────────────────
create table if not exists public.user_subscriptions (
  user_id              uuid primary key references public.profiles (id) on delete cascade,
  tier                 text not null references public.plans (tier),
  status               text not null default 'active'
                         check (status in ('active', 'canceled', 'grace', 'expired')),
  current_period_start timestamptz,
  current_period_end   timestamptz,
  store                text,
  product_id           text,
  updated_at           timestamptz not null default now()
);

-- ── credit_transactions (immutable ledger / audit) ──────────────────────────
create table if not exists public.credit_transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  delta         integer not null,                    -- +grant / +topup, -spend
  reason        text    not null,                    -- grant|spend|topup|trial|legacy_migrate
  balance_after integer,                             -- total spendable after (plan + topup)
  ref           text,                                -- idempotency key (per user)
  tryon_job_id  uuid,
  created_at    timestamptz not null default now(),
  unique (user_id, ref)
);
create index if not exists credit_transactions_user_idx
  on public.credit_transactions (user_id, created_at desc);

-- ── top_up_purchases (idempotent one-off packs) ─────────────────────────────
create table if not exists public.top_up_purchases (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  sku          text not null,
  credits      integer not null,
  price_usd    numeric(8, 2),
  store        text,
  store_txn_id text unique,                           -- idempotent per store transaction
  created_at   timestamptz not null default now()
);

-- ── extend existing tables (additive + defaulted — old clients unaffected) ──
alter table public.credits    add column if not exists topup_balance integer not null default 0;
alter table public.tryon_jobs add column if not exists hd            boolean not null default false;

-- ── grant primitive — the ONE idempotent way credits are added / reset ──────
--  target 'plan'  + set_plan_balance=true  → monthly reset (SET plan balance, no rollover)
--  target 'plan'  + set_plan_balance=false → add to plan balance
--  target 'topup'                          → add to topup_balance (survives reset)
-- Idempotent on (user_id, ref): a repeated ref is a no-op and returns false.
create or replace function public.app_grant_credits(
  p_user             uuid,
  p_amount           integer,
  p_reason           text,
  p_ref              text,
  p_set_plan_balance boolean default false,
  p_target           text    default 'plan'
) returns boolean
language plpgsql
as $$
declare
  v_balance integer;
  v_topup   integer;
begin
  if exists (select 1 from public.credit_transactions
               where user_id = p_user and ref = p_ref) then
    return false;                                    -- already applied
  end if;

  insert into public.credits (user_id) values (p_user)
    on conflict (user_id) do nothing;

  if p_target = 'topup' then
    update public.credits set topup_balance = topup_balance + p_amount, updated_at = now()
       where user_id = p_user returning balance, topup_balance into v_balance, v_topup;
  elsif p_set_plan_balance then
    update public.credits set balance = p_amount, updated_at = now()
       where user_id = p_user returning balance, topup_balance into v_balance, v_topup;
  else
    update public.credits set balance = balance + p_amount, updated_at = now()
       where user_id = p_user returning balance, topup_balance into v_balance, v_topup;
  end if;

  insert into public.credit_transactions (user_id, delta, reason, balance_after, ref)
    values (p_user, p_amount, p_reason, coalesce(v_balance, 0) + coalesce(v_topup, 0), p_ref);
  return true;
end;
$$;

revoke execute on function public.app_grant_credits(uuid, integer, text, text, boolean, text)
  from public;

-- ── RLS — own-row READ only; ALL writes are service-role (server authority) ─
alter table public.plans               enable row level security;
alter table public.user_subscriptions  enable row level security;
alter table public.credit_transactions enable row level security;
alter table public.top_up_purchases    enable row level security;

drop policy if exists plans_select_all on public.plans;
create policy plans_select_all on public.plans
  for select using (true);                            -- pricing/credits are public config

drop policy if exists user_subscriptions_select_own on public.user_subscriptions;
create policy user_subscriptions_select_own on public.user_subscriptions
  for select using (auth.uid() = user_id);

drop policy if exists credit_transactions_select_own on public.credit_transactions;
create policy credit_transactions_select_own on public.credit_transactions
  for select using (auth.uid() = user_id);

drop policy if exists top_up_purchases_select_own on public.top_up_purchases;
create policy top_up_purchases_select_own on public.top_up_purchases
  for select using (auth.uid() = user_id);
-- No INSERT/UPDATE/DELETE policies anywhere above → authenticated users can NEVER
-- write/grant/change tier; the backend writes as the table owner (bypasses RLS).

-- ── legacy tester migration (decision #4) — idempotent ──────────────────────
-- Existing ACTIVE premium testers → Pro Max compatibility: a pro_max subscription
-- for the current period + a ONE-TIME monthly-credit grant (read from plans). The
-- grant ref makes a double-grant impossible on re-run; on_conflict never clobbers
-- a real subscription that may already exist.
do $$
declare
  r         record;
  v_credits integer;
begin
  select monthly_credits into v_credits from public.plans where tier = 'pro_max';
  for r in (select user_id from public.entitlements where active = true) loop
    insert into public.user_subscriptions
        (user_id, tier, status, current_period_start, current_period_end, store, product_id, updated_at)
      values (r.user_id, 'pro_max', 'active', now(), now() + interval '1 month',
              'legacy', 'legacy_premium', now())
      on conflict (user_id) do nothing;
    perform public.app_grant_credits(
      r.user_id, v_credits, 'legacy_migrate',
      'legacy_migrate:' || r.user_id::text, true, 'plan');
  end loop;
end $$;
