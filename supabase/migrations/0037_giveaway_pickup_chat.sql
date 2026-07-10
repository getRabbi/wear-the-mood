-- ============================================================================
-- 0037 — Giveaway Secret Pickup Chat (FEATURES_COMMUNITY_PLUS · Giveaway)
--
-- Private, expiring pickup coordination between a giveaway owner and the ONE
-- requester they accept — so nobody has to share a phone number or address
-- (§10). NOT a general DM system:
--   * a chat exists only after the owner accepts a request;
--   * only owner + accepted requester can read it (RLS below + backend guards);
--   * it stays active for exactly 7 days from approval, then locks;
--   * message bodies are redacted by the cleanup cron after the chat ends —
--     unless the chat is reported, in which case bodies are PRESERVED for
--     moderation review (§19) and only redacted once the flag is cleared;
--   * declined / not-selected requests are purged 72h after they settle.
--
-- Also widens giveaway_claims.status: accepting one request now marks all the
-- other pending ones `not_selected` (never exposing WHO was picked), and a
-- requester can `cancel`; `expired` marks an accepted pickup that timed out.
-- Idempotent. Do NOT touch the baseline (§6).
-- ============================================================================

-- ── giveaway_claims: wider status domain + updated_at (for the 72h purge) ───
alter table public.giveaway_claims
  add column if not exists updated_at timestamptz not null default now();

alter table public.giveaway_claims
  drop constraint if exists giveaway_claims_status_check;
alter table public.giveaway_claims
  add constraint giveaway_claims_status_check
  check (status in ('requested','accepted','declined','not_selected','cancelled','expired'));

-- Cleanup scan: settled claims older than 72h.
create index if not exists giveaway_claims_settled_idx
  on public.giveaway_claims (status, updated_at);

-- ── pickup chats ─────────────────────────────────────────────────────────────
create table if not exists public.giveaway_pickup_chats (
  id               uuid primary key default gen_random_uuid(),
  giveaway_id      uuid not null references public.giveaways (id) on delete cascade,
  claim_id         uuid references public.giveaway_claims (id) on delete set null,
  owner_id         uuid not null references public.profiles (id) on delete cascade,
  requester_id     uuid not null references public.profiles (id) on delete cascade,
  status           text not null default 'active'
                     check (status in ('active','locked','completed','cancelled','expired','reported')),
  -- Coordination card: {"area","landmark","time_slot","confirmed"} — coarse
  -- public-place info only, never a home address (§10).
  pickup_plan      jsonb not null default '{}'::jsonb,
  -- Reported chats are frozen: cleanup must NOT redact bodies while true (§19).
  report_flag      boolean not null default false,
  -- The "expires in <24h" nudge fired (so the cron never double-sends).
  expiry_notified  boolean not null default false,
  approved_at      timestamptz not null default now(),
  expires_at       timestamptz not null,          -- approved_at + 7 days
  locked_at        timestamptz,
  completed_at     timestamptz,
  cancelled_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (giveaway_id, requester_id)              -- one chat per pair per listing
);

-- Only ONE live chat per listing at a time (a new accept after a cancel/expiry
-- creates a new chat; two concurrently active ones can never exist).
create unique index if not exists giveaway_pickup_chats_one_active_idx
  on public.giveaway_pickup_chats (giveaway_id) where status = 'active';

create index if not exists giveaway_pickup_chats_owner_idx
  on public.giveaway_pickup_chats (owner_id);
create index if not exists giveaway_pickup_chats_requester_idx
  on public.giveaway_pickup_chats (requester_id);
-- Cron scan: active chats crossing expires_at.
create index if not exists giveaway_pickup_chats_expiry_idx
  on public.giveaway_pickup_chats (status, expires_at);

-- ── chat messages (text-only, ≤500 chars; bodies are redactable) ────────────
create table if not exists public.giveaway_chat_messages (
  id           uuid primary key default gen_random_uuid(),
  chat_id      uuid not null references public.giveaway_pickup_chats (id) on delete cascade,
  sender_id    uuid not null references public.profiles (id) on delete cascade,
  body         text check (body is null or char_length(body) <= 500),
  body_deleted boolean not null default false,    -- true once redacted
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz
);

create index if not exists giveaway_chat_messages_chat_idx
  on public.giveaway_chat_messages (chat_id, created_at);

-- ── RLS: participants only, ever ─────────────────────────────────────────────
-- The app talks through the FastAPI backend (service-role, which bypasses RLS
-- and re-checks membership per request); these policies are defense-in-depth so
-- a direct Supabase client can never read someone else's pickup chat (§11).
alter table public.giveaway_pickup_chats enable row level security;
alter table public.giveaway_chat_messages enable row level security;

drop policy if exists giveaway_chats_select_participants on public.giveaway_pickup_chats;
create policy giveaway_chats_select_participants on public.giveaway_pickup_chats
  for select using (auth.uid() = owner_id or auth.uid() = requester_id);
-- No insert/update/delete policies: lifecycle writes are backend-only.

drop policy if exists giveaway_chat_messages_select_participants on public.giveaway_chat_messages;
create policy giveaway_chat_messages_select_participants on public.giveaway_chat_messages
  for select using (
    exists (
      select 1 from public.giveaway_pickup_chats c
       where c.id = chat_id
         and (auth.uid() = c.owner_id or auth.uid() = c.requester_id)
    )
  );

-- Direct sends (defense-in-depth; the backend path re-validates the same):
-- sender must be a participant, the chat must still be ACTIVE and inside its
-- 7-day window, and the body must be a real ≤500-char text.
drop policy if exists giveaway_chat_messages_insert_participants on public.giveaway_chat_messages;
create policy giveaway_chat_messages_insert_participants on public.giveaway_chat_messages
  for insert with check (
    auth.uid() = sender_id
    and body is not null
    and body_deleted = false
    and exists (
      select 1 from public.giveaway_pickup_chats c
       where c.id = chat_id
         and (auth.uid() = c.owner_id or auth.uid() = c.requester_id)
         and c.status = 'active'
         and now() < c.expires_at
    )
  );
-- No update/delete policies: redaction is the cleanup cron's job (service role).

-- ── kill-switch flag (§16) ───────────────────────────────────────────────────
-- Seeded ON: the chat replaces off-app contact swaps, so it should be live the
-- moment the giveaway feature itself is on; ops can still kill it remotely.
insert into public.feature_flags (key, enabled, description)
values ('feature_giveaway_chat', true, 'Giveaways: secret 7-day pickup chat after accept')
on conflict (key) do nothing;
