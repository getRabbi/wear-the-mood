-- ============================================================================
-- 0041 — Referral rewards: install attribution + claims (production-grade, §24)
--
-- ADDITIVE + IDEMPOTENT. Builds on the existing profiles.referral_code (0009)
-- and the credit ledger + app_grant_credits primitive (0022). It does NOT touch
-- the legacy public.referrals redemption table or any credit rows.
--
-- Policy: the REFERRER earns a persistent (top-up bucket) bonus exactly once,
-- only after a genuinely NEW account claims via a Play-install-attributed,
-- single-use, time-limited token. The referred user earns 0 in this version.
-- Server is the SOLE authority — the client never grants credits (§11, §25).
-- Designed so iOS can be added later (platform column, no Android-only columns).
-- ============================================================================

-- ── rate_limits (first server-side limiter; generic fixed-window) ───────────
create table if not exists public.rate_limits (
  bucket       text primary key,
  window_start timestamptz not null default now(),
  count        integer     not null default 0
);
alter table public.rate_limits enable row level security;   -- service-role only (no policy)

-- Atomic fixed-window check-and-increment. Returns TRUE when this hit is allowed
-- (within p_max for the current window), FALSE when the limit is exceeded. Works
-- across processes/workers because the counter lives in the DB.
create or replace function public.app_rate_limit(
  p_bucket text, p_max integer, p_window_seconds integer
) returns boolean
language plpgsql
as $$
declare
  v_count integer;
begin
  insert into public.rate_limits (bucket, window_start, count)
    values (p_bucket, now(), 1)
  on conflict (bucket) do update
    set count = case
          when public.rate_limits.window_start
                 < now() - make_interval(secs => p_window_seconds) then 1
          else public.rate_limits.count + 1 end,
        window_start = case
          when public.rate_limits.window_start
                 < now() - make_interval(secs => p_window_seconds) then now()
          else public.rate_limits.window_start end
  returning count into v_count;
  return v_count <= p_max;
end;
$$;
revoke execute on function public.app_rate_limit(text, integer, integer) from public;

-- ── referral_attributions (opaque click/claim token) ────────────────────────
-- The RAW token is never stored or logged — only its sha256 hash. High-entropy,
-- single-use (consumed_at), time-limited (expires_at). One row per click/redirect.
create table if not exists public.referral_attributions (
  id            uuid primary key default gen_random_uuid(),
  token_hash    text        not null unique,
  referrer_id   uuid        not null references public.profiles (id) on delete cascade,
  referral_code text        not null,
  platform      text        not null default 'android',
  created_at    timestamptz not null default now(),   -- click timestamp
  expires_at    timestamptz not null,                 -- click + attribution_window_days
  consumed_at   timestamptz,                           -- set atomically by a claim
  consumed_by   uuid references public.profiles (id) on delete set null
);
create index if not exists referral_attributions_referrer_idx
  on public.referral_attributions (referrer_id);
create index if not exists referral_attributions_expires_idx
  on public.referral_attributions (expires_at);
alter table public.referral_attributions enable row level security; -- service-role only

-- ── referral_claims (the award ledger — one row per SUCCESSFUL referral) ─────
-- Rejections are not stored as blocking rows (they are logged, redacted); only
-- awarded claims live here, so every unique constraint below == "one award per …".
create table if not exists public.referral_claims (
  id               uuid primary key default gen_random_uuid(),
  referrer_id      uuid        not null references public.profiles (id) on delete cascade,
  referred_user_id uuid        not null unique
                     references public.profiles (id) on delete cascade,   -- attributed once
  attribution_id   uuid        not null unique
                     references public.referral_attributions (id) on delete cascade, -- token used once
  install_hash     text,                                 -- HMAC(install id); one award per install
  platform         text        not null default 'android',
  status           text        not null default 'awarded' check (status in ('awarded')),
  reward_credits   integer     not null,
  credit_ref       text        not null unique,          -- 'referral:{id}' — credit-txn idempotency key
  rejection_reason text,                                  -- reserved for future/iOS; awards leave null
  created_at       timestamptz not null default now(),
  credited_at      timestamptz,
  check (referrer_id <> referred_user_id)                -- belt-and-braces self-referral guard
);
-- At most one successful claim per installation.
create unique index if not exists referral_claims_install_hash_key
  on public.referral_claims (install_hash) where install_hash is not null;
create index if not exists referral_claims_referrer_idx
  on public.referral_claims (referrer_id);
alter table public.referral_claims enable row level security;

-- A user may READ their own awarded claims (as the referrer); ALL writes are
-- service-role (server authority). The referred user's identity is never exposed
-- to the referrer via the API — this policy is defense-in-depth only.
drop policy if exists referral_claims_select_referrer on public.referral_claims;
create policy referral_claims_select_referrer on public.referral_claims
  for select using (auth.uid() = referrer_id);
