-- ============================================================================
-- 0051 — Transactional outbox for push delivery (CLAUDE.md §20)
--
-- `create_notification` used to fire the push immediately, with
-- `asyncio.create_task`, from inside whatever transaction the caller happened to
-- be in. Three things were wrong with that:
--
--   * a transaction that later ROLLED BACK still sent a push, for a notification
--     that does not exist;
--   * a push could be tapped before its transaction committed, deep-linking to a
--     conversation or job the reader cannot yet see;
--   * delivery depended on the API process surviving long enough to finish the
--     background task.
--
-- The fix is an outbox: the intent to push is written in the SAME transaction as
-- the notification, and a separate drainer delivers it AFTER that transaction has
-- committed. Rollback removes the intent along with the notification, so an
-- uncommitted action is now incapable of producing a push. Nothing is lost if a
-- process dies mid-send — the row simply stays pending and is retried.
--
-- Additive and idempotent. No existing data is read or modified.
-- ============================================================================

create table if not exists public.notification_outbox (
  id              uuid primary key default gen_random_uuid(),
  -- CASCADE: if the notification is deleted the push intent is meaningless.
  notification_id uuid not null
                    references public.notifications (id) on delete cascade,
  user_id         uuid not null references public.profiles (id) on delete cascade,
  -- title / body / data / android_channel, exactly as the sender needs it. Ids
  -- only inside `data` — never PII (§10).
  payload         jsonb not null,
  attempts        integer not null default 0,
  -- Claim marker, so two drainers never send the same row twice.
  locked_at       timestamptz,
  delivered_at    timestamptz,
  last_error      text,
  created_at      timestamptz not null default now()
);

-- One push intent per notification. The notification insert is already
-- deduplicated by `dedupe_key`, so a collapsed duplicate never reaches this
-- table — but this makes "one notification, one push" true at the schema level
-- rather than by convention.
create unique index if not exists notification_outbox_notification_idx
  on public.notification_outbox (notification_id);

-- The drainer's claim query: oldest undelivered first.
create index if not exists notification_outbox_pending_idx
  on public.notification_outbox (created_at)
  where delivered_at is null;

-- Service-role only. Clients neither read nor write push intents; enabling RLS
-- with NO policies is what makes that true rather than assumed.
alter table public.notification_outbox enable row level security;

comment on table public.notification_outbox is
  'Push-delivery intents, written in the same transaction as their notification '
  'and drained after commit. A rolled-back action produces no row and no push.';
