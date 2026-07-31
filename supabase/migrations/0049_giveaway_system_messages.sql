-- ============================================================================
-- 0049 — Giveaway pickup-chat system messages (CLAUDE.md §1 pillar 4, §10)
--
-- When an owner accepts a requester we open the secret pickup chat, but the two
-- participants land in an empty room with no shared record of what just happened.
-- This adds a first-class SYSTEM message so both sides open the same conversation
-- and immediately see the same accepted state — including after an app restart,
-- because it is a durable row rather than transient client state.
--
-- Idempotent + additive. Existing rows keep working: `kind` defaults to 'user',
-- which is exactly what every message written so far is. No data is deleted.
-- ============================================================================

-- 1) The message kind. 'system' rows are authored by the app, not a participant.
alter table public.giveaway_chat_messages
  add column if not exists kind text not null default 'user';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'giveaway_chat_messages_kind_check'
  ) then
    alter table public.giveaway_chat_messages
      add constraint giveaway_chat_messages_kind_check
      check (kind in ('user', 'system'));
  end if;
end $$;

-- 2) A system message has no human sender. Dropping NOT NULL is a relaxation, so
--    every existing row (all of which have a sender) stays valid.
alter table public.giveaway_chat_messages
  alter column sender_id drop not null;

-- 3) A participant message MUST still name its sender — the relaxation above is
--    only for system rows, and this keeps that honest at the database level.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'giveaway_chat_messages_sender_present'
  ) then
    alter table public.giveaway_chat_messages
      add constraint giveaway_chat_messages_sender_present
      check (kind = 'system' or sender_id is not null);
  end if;
end $$;

-- 4) Idempotency for the accept event: at most ONE 'accepted' system message per
--    chat, so a retried accept (or a re-accept after a cancel) can never stack
--    duplicates. The insert relies on this index for its ON CONFLICT.
create unique index if not exists giveaway_chat_messages_system_once_idx
  on public.giveaway_chat_messages (chat_id, kind)
  where kind = 'system';

-- 5) The messages list reads oldest-first per chat on every poll.
create index if not exists giveaway_chat_messages_chat_created_idx
  on public.giveaway_chat_messages (chat_id, created_at, id);

-- 6) The requester's "my requests" list joins claims -> giveaways by claimer.
--    Without this, finding a user's own claims is a full scan of every claim.
create index if not exists giveaway_claims_claimer_idx
  on public.giveaway_claims (claimer_id, created_at desc);

-- 7) Resolving "does the caller have a chat on this listing" runs for BOTH
--    participants on every giveaway read.
create index if not exists giveaway_pickup_chats_owner_idx
  on public.giveaway_pickup_chats (owner_id, giveaway_id);
create index if not exists giveaway_pickup_chats_requester_idx
  on public.giveaway_pickup_chats (requester_id, giveaway_id);
