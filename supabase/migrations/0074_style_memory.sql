-- ============================================================================
-- 0074 — Style Memory v1: what WTM has learned about a user's taste
--
-- ADDITIVE + IDEMPOTENT. Two brand-new user-owned tables and nothing else; no
-- existing table, column, policy, function or trigger is touched. Every row is
-- RLS-scoped to its owner. With `feature_style_memory` OFF (the default) the
-- app never calls the endpoints that write here, so deploying this migration
-- changes nothing a user can see.
--
-- WHY
-- ---
-- `taste_signals` (baseline, §24) already exists, and is deliberately NOT
-- reused: it is an EMBEDDING store — one pgvector per liked post, averaged into
-- a centroid to bias the stylist. It cannot answer "why", cannot be shown to a
-- user, cannot be corrected by them and cannot be reset independently. Style
-- Memory is the opposite: explicit, legible, editable, resettable, and useful
-- with zero embeddings and zero LLM calls.
--
-- The two coexist. Where a Style Memory signal happens to describe something
-- embeddable, the embedding path stays exactly where it is.
--
-- DESIGN NOTES
--   * The profile is a SUMMARY, updated incrementally from signals. It is never
--     recomputed from raw history on a Home open (§50).
--   * Every inferred preference carries its own confidence AND a source. A
--     preference the USER stated is not the same fact as one we guessed from
--     three renders, and the UI must be able to tell them apart (§12.3).
--   * Signals are append-only and idempotent on an optional dedupe key, so a
--     retried request can never double-weight a preference.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── style_memory_profiles ────────────────────────────────────────────────────
-- One row per user, created lazily on first signal. A missing row means "we
-- have learned nothing yet", which is a legitimate and common state — never an
-- error, and never a reason to invent a preference.
create table if not exists public.style_memory_profiles (
  user_id                 uuid primary key references public.profiles (id) on delete cascade,
  -- Bumped whenever the summary shape changes, so an old client reading a newer
  -- profile can tell rather than mis-parse.
  version                 integer     not null default 1,
  -- 0..1 over the profile as a whole. Drives whether the UI states a
  -- preference at all, and how softly it is worded (§12.3).
  confidence              numeric(4, 3) not null default 0
                            check (confidence >= 0 and confidence <= 1),
  -- Each of these is an ARRAY OF OBJECTS, not a bag of strings:
  --   [{"value": "dark neutral", "weight": 3.0, "confidence": 0.42,
  --     "source": "inferred" | "stated", "updated_at": "..."}]
  -- so a single preference can be shown, corrected or removed on its own.
  preferred_colors        jsonb       not null default '[]'::jsonb,
  avoided_colors          jsonb       not null default '[]'::jsonb,
  preferred_silhouettes   jsonb       not null default '[]'::jsonb,
  avoided_silhouettes     jsonb       not null default '[]'::jsonb,
  preferred_aesthetics    jsonb       not null default '[]'::jsonb,
  preferred_occasions     jsonb       not null default '[]'::jsonb,
  preferred_moods         jsonb       not null default '[]'::jsonb,
  fit_visual_preferences  jsonb       not null default '[]'::jsonb,
  -- One restrained sentence, computed from the above. Never a claim the
  -- underlying confidence does not support.
  preference_summary      text,
  -- The user's own switch. FALSE means: keep their data, stop personalizing
  -- from it. Distinct from a reset, which deletes.
  personalization_enabled boolean     not null default true,
  -- Cheap denominator for confidence, so confidence never needs a count(*).
  signal_count            integer     not null default 0,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

comment on table public.style_memory_profiles is
  'Incrementally-maintained summary of a user''s style preferences. Viewable, '
  'correctable and resettable by the user (§12.2). Never recomputed from raw '
  'signal history on a read.';

alter table public.style_memory_profiles enable row level security;

drop policy if exists style_memory_profiles_select_own on public.style_memory_profiles;
create policy style_memory_profiles_select_own on public.style_memory_profiles
  for select using (auth.uid() = user_id);

drop policy if exists style_memory_profiles_insert_own on public.style_memory_profiles;
create policy style_memory_profiles_insert_own on public.style_memory_profiles
  for insert with check (auth.uid() = user_id);

drop policy if exists style_memory_profiles_update_own on public.style_memory_profiles;
create policy style_memory_profiles_update_own on public.style_memory_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists style_memory_profiles_delete_own on public.style_memory_profiles;
create policy style_memory_profiles_delete_own on public.style_memory_profiles
  for delete using (auth.uid() = user_id);

-- ── style_memory_signals ─────────────────────────────────────────────────────
-- Append-only. The audit trail behind every inferred preference, so "why does
-- WTM think this?" has an answer and a reset has something concrete to delete.
create table if not exists public.style_memory_signals (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  signal_type text not null
                check (signal_type in (
                  'keep_look', 'reject_look', 'save_product', 'unsave_product',
                  'wear_again', 'mood_selected', 'occasion_selected',
                  'share_look', 'save_look', 'manual_preference',
                  'preference_correction', 'preference_removed', 'event_planned'
                )),
  -- What the signal is ABOUT. Free text (no FK): the entity may be a try-on
  -- result, a product, a wardrobe item or nothing at all, and a signal must
  -- outlive the deletion of the thing it describes.
  entity_type text,
  entity_id   text,
  -- The learned content: a reason code for a rejection, a mood or occasion key,
  -- a colour, an aesthetic.
  value       text,
  -- How much this signal moves the summary. A stated preference outweighs an
  -- inferred one; that ordering lives in the service, not here.
  weight      numeric(6, 3) not null default 1,
  source      text not null default 'inferred'
                check (source in ('inferred', 'stated')),
  -- Anything structured worth keeping (mood at the time, occasion, note).
  -- Never an image, never a URL, never a token (§14).
  context     jsonb,
  -- Optional idempotency handle. A retried "keep" for the same result must not
  -- count twice, so the writer passes a stable key and the unique index below
  -- makes the second insert a no-op.
  dedupe_key  text,
  created_at  timestamptz not null default now()
);

comment on table public.style_memory_signals is
  'Append-only evidence behind the Style Memory summary. Idempotent on '
  '(user_id, dedupe_key) where a key is supplied.';

create index if not exists style_memory_signals_user_created_idx
  on public.style_memory_signals (user_id, created_at desc);
create index if not exists style_memory_signals_user_type_idx
  on public.style_memory_signals (user_id, signal_type);
create unique index if not exists style_memory_signals_dedupe_idx
  on public.style_memory_signals (user_id, dedupe_key) where dedupe_key is not null;

alter table public.style_memory_signals enable row level security;

drop policy if exists style_memory_signals_select_own on public.style_memory_signals;
create policy style_memory_signals_select_own on public.style_memory_signals
  for select using (auth.uid() = user_id);

drop policy if exists style_memory_signals_insert_own on public.style_memory_signals;
create policy style_memory_signals_insert_own on public.style_memory_signals
  for insert with check (auth.uid() = user_id);

-- No UPDATE policy on purpose: the table is append-only. A correction is a new
-- signal ('preference_correction'), not an edit of the evidence.

drop policy if exists style_memory_signals_delete_own on public.style_memory_signals;
create policy style_memory_signals_delete_own on public.style_memory_signals
  for delete using (auth.uid() = user_id);

-- ── updated_at trigger, matching the baseline convention ─────────────────────
do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    drop trigger if exists style_memory_profiles_set_updated_at on public.style_memory_profiles;
    create trigger style_memory_profiles_set_updated_at
      before update on public.style_memory_profiles
      for each row execute function public.set_updated_at();
  end if;
end $$;

-- ── the feature flag, seeded OFF ─────────────────────────────────────────────
-- Present so ops can flip it without writing SQL, and OFF so deploying the
-- migration cannot turn anything on (§16).
insert into public.feature_flags (key, enabled, description)
values
  ('feature_style_memory', false,
   'Style Memory v1: signals, summary, view/correct/reset UI.'),
  ('feature_style_memory_feedback', false,
   'Keep it / Not me feedback on the try-on result screen.')
on conflict (key) do nothing;
