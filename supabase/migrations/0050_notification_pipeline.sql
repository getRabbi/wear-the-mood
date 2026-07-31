-- ============================================================================
-- 0050 — Unified notification pipeline (CLAUDE.md §1 pillar 4, §15, §20)
--
-- The notifications table has carried only enough to render a title and a body.
-- Three things were missing for it to work as a real notification system:
--
--   * DEDUPLICATION. Nothing stopped a retried request, a re-delivered webhook or
--     two backend listeners from inserting the same event twice.
--   * DEEP-LINK METADATA. `target_type` + `target_id` alone cannot express "open
--     THIS conversation about THAT giveaway", so a tapped notification could only
--     ever land on the generic inbox.
--   * KEYSET PAGINATION. `order by created_at desc` alone is not a total order,
--     so paging by timestamp silently repeats or skips rows that share a
--     timestamp — which is exactly what a burst of notifications produces.
--
-- Additive and idempotent. Every existing row stays readable: `dedupe_key` and
-- `data` are nullable/defaulted, and no notification is deleted or rewritten.
-- ============================================================================

-- 1) Idempotency key for an event. NULL means "not deduplicated" (legacy rows and
--    any event that is genuinely allowed to repeat), and NULLs do not collide in a
--    unique index, so existing data needs no backfill.
alter table public.notifications
  add column if not exists dedupe_key text;

-- 2) Structured metadata for routing. Anything the app needs to open the exact
--    destination (conversation id, post id, giveaway id …) travels here rather
--    than being re-derived from prose in the title.
alter table public.notifications
  add column if not exists data jsonb not null default '{}'::jsonb;

-- 3) One notification per (recipient, dedupe_key). Scoped to the user so two
--    people can each be told about the same underlying event.
create unique index if not exists notifications_dedupe_idx
  on public.notifications (user_id, dedupe_key)
  where dedupe_key is not null;

-- 4) Total order for keyset pagination. `id` breaks ties so a page boundary that
--    lands inside a group of same-timestamp rows neither repeats nor skips.
create index if not exists notifications_user_keyset_idx
  on public.notifications (user_id, created_at desc, id desc);

-- 5) The unread badge is a COUNT over unread rows; make it an index-only scan.
drop index if exists notifications_unread_idx;
create index if not exists notifications_unread_idx
  on public.notifications (user_id, created_at desc)
  where is_read = false;

-- 6) Push delivery reads a user's live tokens on every single notification.
create index if not exists device_tokens_active_idx
  on public.device_tokens (user_id)
  where invalidated_at is null;

comment on column public.notifications.dedupe_key is
  'Stable idempotency key for the source event. Unique per user; NULL = not deduplicated.';
comment on column public.notifications.data is
  'Structured deep-link metadata (conversation/post/giveaway ids). Never PII.';
