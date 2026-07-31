-- ============================================================================
-- 0052 — Outbox delivery outcomes + retention (CLAUDE.md §20)
--
-- 0051 gave the outbox a `delivered_at`, but the drainer settled EVERY claimed
-- row with it — including rows whose push had actually failed. That records a
-- lie: a transient FCM outage looked identical to a successful delivery, and the
-- row was never retried.
--
-- This adds the states the drainer needs to tell those cases apart, and the
-- retention the table needs so delivered rows do not accumulate forever.
--
-- Additive and idempotent. Existing rows keep working: `status` is derived from
-- the columns already present, so no row changes meaning.
-- ============================================================================

-- 1) Explicit lifecycle. `pending` is the default; the drainer moves a row to
--    exactly one terminal state. `exhausted` is a DEAD LETTER — it must never be
--    confused with `delivered`, which is the whole point of this migration.
alter table public.notification_outbox
  add column if not exists status text not null default 'pending';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notification_outbox_status_check'
  ) then
    alter table public.notification_outbox
      add constraint notification_outbox_status_check
      check (status in ('pending', 'delivered', 'suppressed', 'undeliverable', 'exhausted'));
  end if;
end $$;

-- 2) Backfill from what 0051 already recorded, so history stays truthful:
--    anything with a delivered_at was settled as delivered under the old code.
update public.notification_outbox
   set status = 'delivered'
 where delivered_at is not null and status = 'pending';

-- 3) The claim query filters on status now, not just delivered_at.
drop index if exists notification_outbox_pending_idx;
create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (created_at)
  where status = 'pending';

-- 4) Retention sweep: "delivered/suppressed/undeliverable rows older than N".
--    `exhausted` is deliberately NOT swept — a dead letter is evidence, and it
--    stays until someone has looked at it.
create index if not exists notification_outbox_retention_idx
  on public.notification_outbox (delivered_at)
  where status in ('delivered', 'suppressed', 'undeliverable');

comment on column public.notification_outbox.status is
  'pending | delivered | suppressed (preference off) | undeliverable (no valid '
  'token) | exhausted (dead letter, attempts spent). NEVER mark a failure delivered.';
comment on column public.notification_outbox.last_error is
  'Safe error category for the most recent failed attempt. Never a token, URL or payload.';
