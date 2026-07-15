-- ============================================================================
-- 0043 — Notification preferences: canonical category names + product_updates,
--        and device-token invalidation for FCM pruning (CLAUDE.md §20)
--
-- ADDITIVE + IDEMPOTENT + REVERSIBLE. notification_preferences (0042) is brand
-- new and empty, so the column RENAMES touch no data. Aligns to the canonical
-- 7-category set and adds an invalidated_at marker so a permanently-dead FCM
-- token is deactivated (never deleted, so history + re-registration are intact).
-- Rewrites NO existing rows and drops NO tokens.
-- ============================================================================

-- ── notification_preferences: rename 0042 columns to canonical names ────────
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'notification_preferences'
               and column_name = 'social') then
    alter table public.notification_preferences rename column social to social_activity;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'notification_preferences'
               and column_name = 'referral') then
    alter table public.notification_preferences rename column referral to referral_rewards;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'notification_preferences'
               and column_name = 'account') then
    alter table public.notification_preferences rename column account to account_updates;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'notification_preferences'
               and column_name = 'style') then
    alter table public.notification_preferences rename column style to daily_style;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'notification_preferences'
               and column_name = 'promotions') then
    alter table public.notification_preferences rename column promotions to promotional;
  end if;
end $$;

-- Split "product news & offers": product_updates (ON) vs promotional (opt-in).
alter table public.notification_preferences
  add column if not exists product_updates boolean not null default true;

-- ── device_tokens: mark permanently-dead tokens inactive (never delete) ─────
alter table public.device_tokens
  add column if not exists invalidated_at timestamptz;

create index if not exists device_tokens_active_idx
  on public.device_tokens (user_id) where invalidated_at is null;
