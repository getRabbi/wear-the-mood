-- ============================================================================
-- 0012 — Public profiles + follow graph (CLAUDE.md §1 pillar 4, §5, §10)
-- Adds the safe, *public* fields a creator's profile page needs, REUSING the
-- existing `profiles` table rather than a parallel table (no data to keep in
-- sync). The follow graph already exists (`public.follows`, baseline) with
-- read-public / write-own RLS and a backend self-follow guard — we only add the
-- index that follower/following counts and lists rely on.
--
-- IMPORTANT (privacy, §10): `profiles` also holds SENSITIVE columns (phone,
-- body_data, profile_picture_url, avatar_url = the private try-on photo). We do
-- NOT broaden the `profiles_select_own` RLS to public. The public profile API is
-- served by the backend (service-role) which selects ONLY the safe columns below
-- and honours `is_public`. This keeps sensitive data off public profiles by
-- construction, exactly as the baseline note anticipated.
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- Safe public fields. `username` already exists (baseline).
alter table public.profiles
  add column if not exists bio        text,
  add column if not exists style_tags text[] not null default '{}',
  add column if not exists is_public  boolean not null default true;

-- Follower-count / followers-list queries scan by followee; the follower side
-- (who I follow) uses the PK's leading column. Add the missing followee index.
create index if not exists follows_followee_idx
  on public.follows (followee_id);

-- (RLS unchanged. `follows`: read-public + write-own (follower) from baseline.
--  `profiles`: own-row only — public fields are exposed solely via the backend.)
