-- ============================================================================
-- 0077 — Append-only history for privacy consent decisions
--
-- ADDITIVE + IDEMPOTENT. One new table, one deterministic backfill. Nothing is
-- deleted, nothing is altered, and `user_privacy_consents` — the hot-path
-- table the gate reads on every AI submit — is not touched at all.
--
-- WHY NOW
-- -------
-- `user_privacy_consents` (0066) holds ONE CURRENT ROW per (user, consent_type)
-- and updates it in place. That is the right shape for the gate: "is consent
-- valid at version N" stays a single indexed read on the path of every render.
--
-- But it means a re-grant OVERWRITES the previous decision. Until now that lost
-- nothing anybody needed, because there had only ever been one version. The
-- moment we require a NEW consent version, every existing user re-grants — and
-- the record that they accepted v1, and when, is gone.
--
-- That is precisely the evidence a consent system exists to produce. So the
-- current-state table keeps its shape and gains a companion: an append-only log
-- that no later grant can rewrite.
--
-- WHAT THIS IS NOT
-- ----------------
-- It is NOT a second source of truth. The gate never reads this table. Nothing
-- is authorised or refused on the strength of a row in here. It is evidence,
-- and it is deliberately write-only in normal operation.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

create table if not exists public.user_privacy_consent_events (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  consent_type    text not null,
  -- 'granted' | 'revoked'. The decision the user actually made, not the state
  -- it left behind — a revoke after a revoke is still a decision they took.
  action          text not null check (action in ('granted', 'revoked')),
  -- The version of the disclosure that was ON SCREEN when they decided. This is
  -- the whole point: it records agreement to specific terms at a specific time,
  -- so a later version bump cannot retroactively imply they accepted the newer
  -- ones.
  consent_version integer not null,
  provider_scope  text,
  -- 'app' for a decision made in the product; 'backfill' for the rows this
  -- migration reconstructs from state that predates the log. Marked distinctly
  -- so reconstructed evidence is never mistaken for an observed event.
  source          text not null default 'app',
  created_at      timestamptz not null default now()
);

comment on table public.user_privacy_consent_events is
  'Append-only record of every privacy-consent decision. Evidence only — the '
  'consent GATE reads public.user_privacy_consents and never this table. Rows '
  'are never updated or deleted except by account deletion (FK cascade).';

create index if not exists user_privacy_consent_events_user_idx
  on public.user_privacy_consent_events (user_id, consent_type, created_at desc);

alter table public.user_privacy_consent_events enable row level security;

-- A user may READ their own consent history — it is their record, and the data
-- export owes it to them. Nobody may write through the API: every row is
-- written by the backend with the service role, alongside the state change it
-- describes. An INSERT policy here would let a client fabricate its own
-- evidence of consent, which is the one thing an audit log must never allow.
drop policy if exists user_privacy_consent_events_select_own
  on public.user_privacy_consent_events;
create policy user_privacy_consent_events_select_own
  on public.user_privacy_consent_events
  for select using (auth.uid() = user_id);

-- ── backfill: represent the grants that already exist ────────────────────────
--
-- Every current row in `user_privacy_consents` describes a decision that really
-- happened; without this, the log would open empty and the v1 acceptances would
-- look as though they never occurred.
--
-- Deterministic and restartable: guarded on `source = 'backfill'` for the same
-- (user, type, version), so re-running inserts nothing a second time. It uses
-- the row's OWN granted_at/revoked_at rather than now(), so the reconstructed
-- timestamps are the real ones.
insert into public.user_privacy_consent_events
  (user_id, consent_type, action, consent_version, provider_scope, source, created_at)
select c.user_id,
       c.consent_type,
       case when c.revoked_at is null then 'granted' else 'revoked' end,
       c.consent_version,
       c.provider_scope,
       'backfill',
       coalesce(c.revoked_at, c.granted_at)
  from public.user_privacy_consents c
 where not exists (
   select 1 from public.user_privacy_consent_events e
    where e.user_id = c.user_id
      and e.consent_type = c.consent_type
      and e.consent_version = c.consent_version
      and e.source = 'backfill'
 );
