-- ============================================================================
-- 0042 — Per-category notification preferences (CLAUDE.md §20)
--
-- ADDITIVE + IDEMPOTENT. One row per user with a boolean PUSH toggle per
-- category. These gate PUSH DELIVERY only — the durable notification record is
-- always created (it is the source of truth; the in-app center is unaffected).
-- Promotional push is OFF by default (opt-in only); everything else defaults ON.
-- A missing row means all-defaults, so provisioning is lazy. Own-row read RLS;
-- all writes are service-role (the backend scopes by the JWT user_id, §11).
-- ============================================================================

create table if not exists public.notification_preferences (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  social      boolean not null default true,   -- follows, likes, comments, replies, mentions
  referral    boolean not null default true,   -- referral rewards
  account     boolean not null default true,   -- account, billing, AI job results
  community   boolean not null default true,   -- giveaways, challenges
  style       boolean not null default true,   -- daily style reminders
  promotions  boolean not null default false,  -- product news & offers — OPT-IN only
  updated_at  timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_select_own on public.notification_preferences;
create policy notification_preferences_select_own on public.notification_preferences
  for select using (auth.uid() = user_id);
