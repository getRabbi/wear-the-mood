-- ============================================================================
-- 0024 — Admin & Moderation console foundation
-- (BUILD_PROMPT_ADMIN_PANEL_PERFECT_FINAL.md §10–§11; CLAUDE.md §5, §10, §19)
--
-- Phase 1 = SCHEMA + AUDIT FOUNDATION ONLY. No app/console wiring yet.
--
-- Adds the data the private admin console needs to moderate the live community:
--   * admin_users            — the allowlist + role of who may use the console
--   * admin_audit_log        — append-only record of every admin mutation (§4.4)
--   * profiles/posts/comments — moderation-state columns (status/ban/seed/…)
--   * reports                — EXTENDED in place (do NOT create moderation_reports)
--   * moderation_appeals / moderation_actions / user_strikes / admin_notes
--   * seed_accounts          — official WTM Studio / inspiration accounts (§5)
--   * app_config             — admin/ops feature config (seed flag, maintenance…)
--   * notification_campaigns — admin broadcast push (sent by the FCM service later)
--   * audited RPCs           — high-risk mutations that write the audit row in the
--                              SAME transaction as the mutation (§7.5)
--
-- DESIGN DECISIONS (founder-approved):
--   (b) reports is EXTENDED, not duplicated. No status CHECK is imposed so the
--       existing free-text 'open' rows stay valid; the console maps them.
--   (c) Admin credit changes REUSE credit_transactions + app_grant_credits()
--       (0022) via admin_adjust_credits(); NO parallel credit_adjustments table.
--   (d) Legacy Supabase keys stay. New admin tables are SERVICE-ROLE ONLY (RLS on,
--       no policy) — mirroring idempotency_keys/ai_usage_log — so the mobile app
--       (anon/authenticated) can never read admin/moderation data. The console
--       reads via the server-only service_role key; the backend via direct PG.
--
-- Idempotent + re-runnable (create…if not exists / add column if not exists /
-- guarded DO blocks / create or replace). Additive + defaulted, so existing
-- mobile clients are unaffected. Touches NOTHING in the free 2D try-on path.
-- Do NOT edit FASHIONOS_BASELINE.sql (§6). Apply to DEV first, verify, then prod.
-- ============================================================================

-- ── admin_users (allowlist + role; the real security boundary, §2/§6) ───────
create table if not exists public.admin_users (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  email      text not null,
  role       text not null default 'moderator'
               check (role in ('owner', 'admin', 'moderator', 'support', 'content_manager')),
  status     text not null default 'active'
               check (status in ('active', 'disabled', 'revoked')),
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id)
);
create index if not exists idx_admin_users_role   on public.admin_users (role);
create index if not exists idx_admin_users_status on public.admin_users (status);

-- ── admin_audit_log (append-only; OWASP logging, §4.4) ──────────────────────
create table if not exists public.admin_audit_log (
  id          bigint generated always as identity primary key,
  admin_id    uuid references auth.users (id),
  admin_email text,
  action      text not null,
  target_type text not null,
  target_id   text,
  reason      text,
  metadata    jsonb not null default '{}',
  before_data jsonb,
  after_data  jsonb,
  ip_address  text,
  user_agent  text,
  request_id  text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_admin_audit_created on public.admin_audit_log (created_at desc);
create index if not exists idx_admin_audit_admin   on public.admin_audit_log (admin_id, created_at desc);
create index if not exists idx_admin_audit_target  on public.admin_audit_log (target_type, target_id);
create index if not exists idx_admin_audit_action  on public.admin_audit_log (action);

-- ── profiles: user moderation + seed state (additive, defaulted) ────────────
alter table public.profiles
  add column if not exists account_status text not null default 'active'
    check (account_status in
      ('active', 'suspended', 'banned', 'shadowbanned', 'deleted', 'archived')),
  add column if not exists ban_reason          text,
  add column if not exists banned_at           timestamptz,
  add column if not exists banned_until        timestamptz,
  add column if not exists moderated_by        uuid references auth.users (id),
  add column if not exists deleted_at          timestamptz,
  add column if not exists is_seed             boolean not null default false,
  add column if not exists is_official         boolean not null default false,
  add column if not exists public_label        text,
  add column if not exists created_by_admin_id uuid references auth.users (id);

create index if not exists idx_profiles_account_status on public.profiles (account_status);
create index if not exists idx_profiles_is_seed        on public.profiles (is_seed);
create index if not exists idx_profiles_deleted_at     on public.profiles (deleted_at);

-- ── posts: moderation + seed state ──────────────────────────────────────────
-- NOTE: this `status` (moderation) is ORTHOGONAL to the existing `visibility`
-- (the author's public/private choice). The feed will require BOTH
-- status='published' AND visibility='public' (wired in a later phase).
alter table public.posts
  add column if not exists status text not null default 'published'
    check (status in ('published', 'hidden', 'deleted', 'archived')),
  add column if not exists is_seed             boolean not null default false,
  add column if not exists is_official         boolean not null default false,
  add column if not exists moderated_by        uuid references auth.users (id),
  add column if not exists moderation_reason   text,
  add column if not exists deleted_at          timestamptz,
  add column if not exists hidden_at           timestamptz,
  add column if not exists featured_at         timestamptz,
  add column if not exists pinned_until        timestamptz,
  add column if not exists created_by_admin_id uuid references auth.users (id);

create index if not exists idx_posts_status      on public.posts (status);
create index if not exists idx_posts_is_seed     on public.posts (is_seed);
create index if not exists idx_posts_featured_at on public.posts (featured_at desc);
create index if not exists idx_posts_deleted_at  on public.posts (deleted_at);

-- ── comments: moderation state ──────────────────────────────────────────────
alter table public.comments
  add column if not exists status text not null default 'published'
    check (status in ('published', 'hidden', 'deleted')),
  add column if not exists moderated_by      uuid references auth.users (id),
  add column if not exists moderation_reason text,
  add column if not exists deleted_at        timestamptz,
  add column if not exists hidden_at         timestamptz;

create index if not exists idx_comments_status     on public.comments (status);
create index if not exists idx_comments_deleted_at on public.comments (deleted_at);

-- ── reports: EXTEND the existing baseline table (decision (b)) ──────────────
-- Existing columns: reporter_id, subject_type, subject_id, reason, status
--   ('open' default, free text), created_at. We ADD only the review/queue fields.
-- We deliberately do NOT add a status CHECK constraint: the column already holds
-- 'open' and is free text; the console treats 'open' as the Pending bucket and
-- writes the canonical values ('pending','reviewing','actioned','dismissed').
alter table public.reports
  add column if not exists reported_user_id uuid references public.profiles (id),
  add column if not exists details          text,
  add column if not exists reviewed_by      uuid references auth.users (id),
  add column if not exists reviewed_at       timestamptz,
  add column if not exists admin_note        text,
  add column if not exists updated_at        timestamptz not null default now();

create index if not exists idx_reports_status  on public.reports (status, created_at desc);
create index if not exists idx_reports_subject on public.reports (subject_type, subject_id);
create index if not exists idx_reports_reporter on public.reports (reporter_id, created_at desc);

-- ── moderation_appeals (user-submitted; admin-reviewed) ─────────────────────
create table if not exists public.moderation_appeals (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users (id),
  target_type   text not null check (target_type in ('user', 'post', 'comment')),
  target_id     text,
  action_log_id bigint references public.admin_audit_log (id),
  message       text not null,
  status        text not null default 'pending'
                  check (status in ('pending', 'reviewing', 'approved', 'denied')),
  reviewed_by   uuid references auth.users (id),
  reviewed_at   timestamptz,
  admin_note    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists idx_moderation_appeals_status
  on public.moderation_appeals (status, created_at desc);
create index if not exists idx_moderation_appeals_user
  on public.moderation_appeals (user_id, created_at desc);

-- ── moderation_actions (flat history of enforcement, for fast per-target reads)
create table if not exists public.moderation_actions (
  id             bigint generated always as identity primary key,
  admin_id       uuid references auth.users (id),
  action         text not null,
  target_type    text not null,
  target_id      text not null,
  target_user_id uuid references auth.users (id),
  reason         text not null,
  metadata       jsonb not null default '{}',
  created_at     timestamptz not null default now()
);
create index if not exists idx_moderation_actions_target
  on public.moderation_actions (target_type, target_id);
create index if not exists idx_moderation_actions_user
  on public.moderation_actions (target_user_id, created_at desc);

-- ── user_strikes ────────────────────────────────────────────────────────────
create table if not exists public.user_strikes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users (id),
  report_id  bigint,
  action_id  bigint references public.moderation_actions (id),
  severity   text not null default 'medium'
               check (severity in ('low', 'medium', 'high', 'critical')),
  reason     text not null,
  expires_at timestamptz,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);
create index if not exists idx_user_strikes_user on public.user_strikes (user_id, created_at desc);

-- ── admin_notes (free-form notes attached to any moderation target) ─────────
create table if not exists public.admin_notes (
  id          bigint generated always as identity primary key,
  target_type text not null
                check (target_type in
                  ('user', 'post', 'comment', 'report', 'appeal',
                   'subscription', 'credit_adjustment')),
  target_id   text not null,
  note        text not null,
  created_by  uuid references auth.users (id),
  created_at  timestamptz not null default now()
);
create index if not exists idx_admin_notes_target
  on public.admin_notes (target_type, target_id, created_at desc);

-- ── seed_accounts (official WTM Studio / inspiration accounts, §5) ──────────
-- Each row points at a REAL auth.users id (created via the Supabase Admin API in
-- a later phase; the on_auth_user_created trigger auto-provisions profile+credits).
-- The corresponding profile is flagged is_seed/is_official + public_label.
create table if not exists public.seed_accounts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null unique references auth.users (id) on delete cascade,
  display_name text not null,
  username     text not null unique,
  seed_type    text not null default 'studio'
                 check (seed_type in ('studio', 'lookbook', 'inspiration', 'campaign')),
  status       text not null default 'active'
                 check (status in ('active', 'paused', 'archived', 'deleted')),
  public_label text not null default 'WTM Studio',
  created_by   uuid references auth.users (id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_seed_accounts_status on public.seed_accounts (status);

-- ── app_config (admin/ops feature config) ───────────────────────────────────
create table if not exists public.app_config (
  key        text primary key,
  value      jsonb not null,
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null default now()
);
insert into public.app_config (key, value) values
  ('seed_accounts_enabled',          'true'::jsonb),
  ('maintenance_mode',               'false'::jsonb),
  ('public_official_badges_enabled', 'true'::jsonb)
on conflict (key) do nothing;

-- ── notification_campaigns (admin broadcast push; sent by the FCM service) ──
create table if not exists public.notification_campaigns (
  id             bigint generated always as identity primary key,
  title          text not null,
  body           text not null,
  target_segment text not null default 'all',
  status         text not null default 'draft'
                   check (status in ('draft', 'scheduled', 'sent', 'cancelled', 'failed')),
  scheduled_at   timestamptz,
  sent_at        timestamptz,
  created_by     uuid references auth.users (id),
  metadata       jsonb not null default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists idx_notification_campaigns_status
  on public.notification_campaigns (status, created_at desc);

-- ============================================================================
-- updated_at triggers for the new mutable tables
-- ============================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'admin_users', 'reports', 'moderation_appeals', 'seed_accounts',
    'app_config', 'notification_campaigns'
  ]
  loop
    execute format('drop trigger if exists trg_%1$s_updated_at on public.%1$s;', t);
    execute format(
      'create trigger trg_%1$s_updated_at before update on public.%1$s
         for each row execute function public.set_updated_at();', t);
  end loop;
end;
$$;

-- ============================================================================
-- Row Level Security — admin/moderation tables are SERVICE-ROLE ONLY (decision
-- (d)). RLS on + NO policy => anon/authenticated (the mobile app) read nothing;
-- service_role (console server) bypasses RLS; the backend uses a direct PG conn.
-- EXCEPTION: moderation_appeals gets own-row insert/select so a user can file +
-- see their OWN appeal later (mirrors how `reports` is exposed). reports RLS is
-- left UNCHANGED from baseline (insert-own / select-own).
-- ============================================================================
alter table public.admin_users            enable row level security;
alter table public.admin_audit_log        enable row level security;
alter table public.moderation_appeals     enable row level security;
alter table public.moderation_actions     enable row level security;
alter table public.user_strikes           enable row level security;
alter table public.admin_notes            enable row level security;
alter table public.seed_accounts          enable row level security;
alter table public.app_config             enable row level security;
alter table public.notification_campaigns enable row level security;

-- Appeals: a user may file + read their OWN appeals (admin reads via service role).
drop policy if exists moderation_appeals_insert_own on public.moderation_appeals;
create policy moderation_appeals_insert_own on public.moderation_appeals
  for insert with check (auth.uid() = user_id);
drop policy if exists moderation_appeals_select_own on public.moderation_appeals;
create policy moderation_appeals_select_own on public.moderation_appeals
  for select using (auth.uid() = user_id);

-- Append-only hardening for the audit log: strip ALL write privileges from the
-- mobile-app roles so history can never be inserted, altered, or truncated by a
-- normal user — even if an RLS policy is ever added by mistake. Audit rows are
-- written only by admin_log_audit() (SECURITY DEFINER, runs as owner) and by the
-- backend's direct owner connection; service_role (the console) bypasses RLS for
-- reads. None of those paths need the `authenticated`/`anon` grants.
revoke insert, update, delete, truncate on public.admin_audit_log from authenticated, anon;

-- ============================================================================
-- Audited mutation RPCs (§7.5 — mutation + audit in ONE transaction).
--
-- TRUST MODEL: every function is SECURITY DEFINER with a pinned search_path and
-- is callable ONLY by service_role (revoked from public/anon/authenticated). The
-- Next.js Server Action re-verifies admin identity + the FULL permission matrix
-- BEFORE calling; each RPC additionally asserts the caller is an ACTIVE admin
-- (defense-in-depth) and that a reason is present where required. Because a
-- plpgsql function body is one transaction, the target mutation + moderation_actions
-- + admin_audit_log rows commit or roll back together — never half-applied.
--
-- NOT done as RPC (documented for later phases): push-campaign SEND and
-- RevenueCat refund/comp run through FastAPI admin endpoints because they call
-- backend services (FCM, RevenueCat) — those endpoints open a DB transaction and
-- insert the audit row in the same transaction (the §7.5 FastAPI variant).
-- ============================================================================

-- helper: assert an active admin (raises 42501 / insufficient_privilege) --------
create or replace function public.admin_assert_active(p_admin_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_admin_id is null
     or not exists (
       select 1 from public.admin_users
        where user_id = p_admin_id and status = 'active'
     ) then
    raise exception 'NOT_ADMIN: % is not an active admin', p_admin_id
      using errcode = '42501';
  end if;
end;
$$;

-- helper: write one audit row, return its id ----------------------------------
create or replace function public.admin_log_audit(
  p_admin_id    uuid,
  p_admin_email text,
  p_action      text,
  p_target_type text,
  p_target_id   text,
  p_reason      text,
  p_metadata    jsonb,
  p_before      jsonb,
  p_after       jsonb
) returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  insert into public.admin_audit_log
    (admin_id, admin_email, action, target_type, target_id,
     reason, metadata, before_data, after_data)
  values
    (p_admin_id, p_admin_email, p_action, p_target_type, p_target_id,
     p_reason, coalesce(p_metadata, '{}'::jsonb), p_before, p_after)
  returning id into v_id;
  return v_id;
end;
$$;

-- helper: a profile's moderation snapshot (for before/after diffs) -------------
create or replace function public.admin_profile_snapshot(p_user_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select to_jsonb(s) from (
    select account_status, ban_reason, banned_at, banned_until,
           moderated_by, deleted_at
      from public.profiles where id = p_user_id
  ) s;
$$;

-- helper: require a non-blank reason ------------------------------------------
create or replace function public.admin_require_reason(p_reason text)
returns void
language plpgsql
immutable
as $$
begin
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'REASON_REQUIRED' using errcode = '23514';
  end if;
end;
$$;

-- ── user actions ────────────────────────────────────────────────────────────

create or replace function public.admin_suspend_user(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_banned_until timestamptz, p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_profile_snapshot(p_target_user_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.profiles
     set account_status = 'suspended', ban_reason = p_reason,
         banned_at = now(), banned_until = p_banned_until, moderated_by = p_admin_id
   where id = p_target_user_id;
  v_after := admin_profile_snapshot(p_target_user_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'suspend_user', 'user', p_target_user_id::text,
          p_target_user_id, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'suspend_user', 'user',
           p_target_user_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_ban_user(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_profile_snapshot(p_target_user_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.profiles
     set account_status = 'banned', ban_reason = p_reason,
         banned_at = now(), banned_until = null, moderated_by = p_admin_id
   where id = p_target_user_id;
  v_after := admin_profile_snapshot(p_target_user_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'ban_user', 'user', p_target_user_id::text,
          p_target_user_id, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'ban_user', 'user',
           p_target_user_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_shadowban_user(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_profile_snapshot(p_target_user_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.profiles
     set account_status = 'shadowbanned', ban_reason = p_reason,
         banned_at = now(), moderated_by = p_admin_id
   where id = p_target_user_id;
  v_after := admin_profile_snapshot(p_target_user_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'shadowban_user', 'user', p_target_user_id::text,
          p_target_user_id, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'shadowban_user', 'user',
           p_target_user_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_restore_user(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_profile_snapshot(p_target_user_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.profiles
     set account_status = 'active', ban_reason = null, banned_at = null,
         banned_until = null, deleted_at = null, moderated_by = p_admin_id
   where id = p_target_user_id;
  v_after := admin_profile_snapshot(p_target_user_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'restore_user', 'user', p_target_user_id::text,
          p_target_user_id, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'restore_user', 'user',
           p_target_user_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

-- Soft delete = mark deleted (status + deleted_at). Hard delete + full anonymize
-- is OWNER-only and handled separately (auth.users cascade) in a later phase.
create or replace function public.admin_soft_delete_user(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  v_before := admin_profile_snapshot(p_target_user_id);
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;
  update public.profiles
     set account_status = 'deleted', deleted_at = now(), moderated_by = p_admin_id
   where id = p_target_user_id;
  v_after := admin_profile_snapshot(p_target_user_id);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'soft_delete_user', 'user', p_target_user_id::text,
          p_target_user_id, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'soft_delete_user', 'user',
           p_target_user_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

-- ── post actions ────────────────────────────────────────────────────────────

create or replace function public.admin_hide_post(
  p_admin_id uuid, p_admin_email text, p_post_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_post_id using errcode = 'P0002';
  end if;
  update public.posts
     set status = 'hidden', hidden_at = now(),
         moderation_reason = p_reason, moderated_by = p_admin_id
   where id = p_post_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'hide_post', 'post', p_post_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'hide_post', 'post',
           p_post_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_restore_post(
  p_admin_id uuid, p_admin_email text, p_post_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_post_id using errcode = 'P0002';
  end if;
  update public.posts
     set status = 'published', hidden_at = null, deleted_at = null,
         moderation_reason = null, moderated_by = p_admin_id
   where id = p_post_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'restore_post', 'post', p_post_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'restore_post', 'post',
           p_post_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

-- Soft delete (status='deleted'); the public image teardown stays in the app/API
-- delete path. Hard delete of a post stays a separate, explicit action.
create or replace function public.admin_delete_post(
  p_admin_id uuid, p_admin_email text, p_post_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_post_id using errcode = 'P0002';
  end if;
  update public.posts
     set status = 'deleted', deleted_at = now(),
         moderation_reason = p_reason, moderated_by = p_admin_id
   where id = p_post_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.posts where id = p_post_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'delete_post', 'post', p_post_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'delete_post', 'post',
           p_post_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

-- ── comment actions ─────────────────────────────────────────────────────────

create or replace function public.admin_hide_comment(
  p_admin_id uuid, p_admin_email text, p_comment_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_comment_id using errcode = 'P0002';
  end if;
  update public.comments
     set status = 'hidden', hidden_at = now(),
         moderation_reason = p_reason, moderated_by = p_admin_id
   where id = p_comment_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'hide_comment', 'comment', p_comment_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'hide_comment', 'comment',
           p_comment_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_restore_comment(
  p_admin_id uuid, p_admin_email text, p_comment_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_comment_id using errcode = 'P0002';
  end if;
  update public.comments
     set status = 'published', hidden_at = null, deleted_at = null,
         moderation_reason = null, moderated_by = p_admin_id
   where id = p_comment_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'restore_comment', 'comment', p_comment_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'restore_comment', 'comment',
           p_comment_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

create or replace function public.admin_delete_comment(
  p_admin_id uuid, p_admin_email text, p_comment_id uuid,
  p_reason text, p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_author uuid;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  select to_jsonb(s), s.user_id into v_before, v_author
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  if v_before is null then
    raise exception 'TARGET_NOT_FOUND: %', p_comment_id using errcode = 'P0002';
  end if;
  update public.comments
     set status = 'deleted', deleted_at = now(),
         moderation_reason = p_reason, moderated_by = p_admin_id
   where id = p_comment_id;
  select to_jsonb(s) into v_after
    from (select id, user_id, status, moderation_reason, hidden_at, deleted_at
            from public.comments where id = p_comment_id) s;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'delete_comment', 'comment', p_comment_id::text,
          v_author, p_reason, coalesce(p_metadata, '{}'::jsonb));
  return admin_log_audit(p_admin_id, p_admin_email, 'delete_comment', 'comment',
           p_comment_id::text, p_reason, p_metadata, v_before, v_after);
end;
$$;

-- ── credit adjustment (decision (c): REUSE app_grant_credits + ledger) ──────
-- Adds (or, for a negative amount, deducts from the PLAN balance) credits, then
-- audits. Idempotent on p_ref (pass a stable client-action id to make a retry a
-- no-op; defaults to a fresh uuid). A negative amount may not exceed the current
-- PLAN balance (top-up is never silently drained by an admin deduct).
create or replace function public.admin_adjust_credits(
  p_admin_id uuid, p_admin_email text, p_target_user_id uuid,
  p_amount integer, p_reason text, p_ref text default null,
  p_metadata jsonb default '{}'::jsonb
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_ref     text;
  v_before  integer;
  v_after   integer;
  v_plan    integer;
  v_applied boolean;
  v_meta    jsonb;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  if p_amount = 0 then
    raise exception 'AMOUNT_ZERO' using errcode = '23514';
  end if;
  if not exists (select 1 from public.profiles where id = p_target_user_id) then
    raise exception 'TARGET_NOT_FOUND: %', p_target_user_id using errcode = 'P0002';
  end if;

  insert into public.credits (user_id) values (p_target_user_id)
    on conflict (user_id) do nothing;
  select balance, balance + topup_balance into v_plan, v_before
    from public.credits where user_id = p_target_user_id;
  if p_amount < 0 and v_plan + p_amount < 0 then
    raise exception 'INSUFFICIENT_BALANCE: plan balance % cannot absorb %', v_plan, p_amount
      using errcode = '23514';
  end if;

  v_ref := coalesce(nullif(btrim(coalesce(p_ref, '')), ''),
                    'admin_adjust:' || gen_random_uuid()::text);
  v_applied := public.app_grant_credits(
    p_target_user_id, p_amount, 'admin_adjust', v_ref, false, 'plan');

  select balance + topup_balance into v_after
    from public.credits where user_id = p_target_user_id;

  v_meta := coalesce(p_metadata, '{}'::jsonb)
            || jsonb_build_object('amount', p_amount, 'ref', v_ref, 'applied', v_applied);
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'adjust_credits', 'credit_adjustment', p_target_user_id::text,
          p_target_user_id, p_reason, v_meta);
  return admin_log_audit(
    p_admin_id, p_admin_email, 'adjust_credits', 'credit_adjustment',
    p_target_user_id::text, p_reason, v_meta,
    jsonb_build_object('total_available', v_before),
    jsonb_build_object('total_available', v_after));
end;
$$;

-- ── seed winddown: archive ALL seed posts (one of the §5 winddown tools) ────
create or replace function public.admin_archive_all_seed_content(
  p_admin_id uuid, p_admin_email text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_posts integer;
begin
  perform admin_assert_active(p_admin_id);
  perform admin_require_reason(p_reason);
  update public.posts set status = 'archived', moderated_by = p_admin_id
   where is_seed = true and status <> 'archived';
  get diagnostics v_posts = row_count;
  insert into public.moderation_actions
    (admin_id, action, target_type, target_id, target_user_id, reason, metadata)
  values (p_admin_id, 'archive_all_seed_content', 'seed', 'all', null, p_reason,
          jsonb_build_object('posts_archived', v_posts));
  return admin_log_audit(
    p_admin_id, p_admin_email, 'archive_all_seed_content', 'seed', 'all',
    p_reason, jsonb_build_object('posts_archived', v_posts), null, null);
end;
$$;

-- ── execution grants: service_role only (console RPC path); revoke the rest ─
-- The backend's direct PG connection (owner) can always execute. The console
-- calls these via PostgREST as service_role, so it needs EXECUTE; anon /
-- authenticated (the mobile app) must NOT.
do $$
declare
  fn text;
begin
  foreach fn in array array[
    'admin_assert_active(uuid)',
    'admin_log_audit(uuid,text,text,text,text,text,jsonb,jsonb,jsonb)',
    'admin_profile_snapshot(uuid)',
    'admin_require_reason(text)',
    'admin_suspend_user(uuid,text,uuid,timestamptz,text,jsonb)',
    'admin_ban_user(uuid,text,uuid,text,jsonb)',
    'admin_shadowban_user(uuid,text,uuid,text,jsonb)',
    'admin_restore_user(uuid,text,uuid,text,jsonb)',
    'admin_soft_delete_user(uuid,text,uuid,text,jsonb)',
    'admin_hide_post(uuid,text,uuid,text,jsonb)',
    'admin_restore_post(uuid,text,uuid,text,jsonb)',
    'admin_delete_post(uuid,text,uuid,text,jsonb)',
    'admin_hide_comment(uuid,text,uuid,text,jsonb)',
    'admin_restore_comment(uuid,text,uuid,text,jsonb)',
    'admin_delete_comment(uuid,text,uuid,text,jsonb)',
    'admin_adjust_credits(uuid,text,uuid,integer,text,text,jsonb)',
    'admin_archive_all_seed_content(uuid,text,text)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end;
$$;

-- ============================================================================
-- End of 0024
-- ============================================================================
