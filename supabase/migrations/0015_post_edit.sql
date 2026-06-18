-- ============================================================================
-- 0015 — Post editing (FEATURES_COMMUNITY_PLUS · Post Edit)
--
-- Additive + backward-compatible: lets a user edit their OWN post. We record
-- whether/when a post was edited so the feed can show a subtle "edited" label.
-- The edit endpoint re-runs content moderation on the new text/image (§19) and
-- RLS already scopes writes to the owner. Also seeds the feature_post_edit flag
-- (OFF) so the feature stays dark until enabled for rollout (§16).
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

alter table public.posts
  add column if not exists is_edited boolean not null default false;

alter table public.posts
  add column if not exists edited_at timestamptz;

insert into public.feature_flags (key, enabled, description)
values ('feature_post_edit', false, 'Community: edit your own post')
on conflict (key) do nothing;
