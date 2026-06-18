-- ============================================================================
-- 0017 — Style Quiz (FEATURES_COMMUNITY_PLUS · Style Quiz)
--
-- A short, shareable quiz whose result is a "Style DNA" card AND quietly feeds
-- the taste graph. quizzes/quiz_questions are public content; quiz_responses are
-- own-row (a user's answers + computed result). Seeds the "style-dna" quiz with
-- its questions and the feature_style_quiz flag (OFF, §16). Each option's `key`
-- is a style trait the backend tallies into the result.
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

create table if not exists public.quizzes (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  title       text not null,
  description text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id          uuid primary key default gen_random_uuid(),
  quiz_id     uuid not null references public.quizzes (id) on delete cascade,
  order_index int  not null,
  prompt      text not null,
  options     jsonb not null,            -- [{key, label, image_url?}]
  unique (quiz_id, order_index)
);

create table if not exists public.quiz_responses (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  quiz_id    uuid not null references public.quizzes (id) on delete cascade,
  answers    jsonb not null,             -- {question_id: option_key}
  result     jsonb not null,             -- {title, keywords, description, palette}
  created_at timestamptz not null default now()
);

create index if not exists quiz_responses_user_idx
  on public.quiz_responses (user_id, created_at desc);

alter table public.quizzes        enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_responses enable row level security;

-- Quizzes + questions are public content (read-public); writes are service-role.
drop policy if exists quizzes_select_public on public.quizzes;
create policy quizzes_select_public on public.quizzes for select using (true);
drop policy if exists quiz_questions_select_public on public.quiz_questions;
create policy quiz_questions_select_public on public.quiz_questions for select using (true);

-- Responses are private: own-row read + write.
drop policy if exists quiz_responses_rw_own on public.quiz_responses;
create policy quiz_responses_rw_own on public.quiz_responses
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Seed the Style DNA quiz ─────────────────────────────────────────────────
insert into public.quizzes (slug, title, description, is_active)
values ('style-dna', 'Style DNA',
        'Answer a few quick questions to reveal your Style DNA.', true)
on conflict (slug) do nothing;

insert into public.quiz_questions (quiz_id, order_index, prompt, options)
select q.id, v.order_index, v.prompt, v.options::jsonb
  from public.quizzes q
  cross join (values
    (0, 'Pick a vibe for a day out', $$[
      {"key":"minimal","label":"Clean & understated"},
      {"key":"bold","label":"Statement & vibrant"},
      {"key":"earthy","label":"Warm & natural"},
      {"key":"street","label":"Urban & relaxed"}
    ]$$),
    (1, 'Your ideal colour palette', $$[
      {"key":"minimal","label":"Monochrome & neutral"},
      {"key":"earthy","label":"Terracotta & olive"},
      {"key":"romantic","label":"Soft pastels"},
      {"key":"bold","label":"Bright & saturated"}
    ]$$),
    (2, 'Your go-to weekend outfit', $$[
      {"key":"classic","label":"Tailored & timeless"},
      {"key":"street","label":"Hoodie & sneakers"},
      {"key":"romantic","label":"A flowy dress"},
      {"key":"minimal","label":"Tee & straight trousers"}
    ]$$),
    (3, 'A piece you can''t live without', $$[
      {"key":"classic","label":"A crisp white shirt"},
      {"key":"bold","label":"A statement jacket"},
      {"key":"earthy","label":"A chunky knit"},
      {"key":"romantic","label":"A floral midi"}
    ]$$),
    (4, 'Your style icon leans', $$[
      {"key":"minimal","label":"Scandi minimalist"},
      {"key":"classic","label":"Old-money classic"},
      {"key":"street","label":"Streetwear"},
      {"key":"romantic","label":"Boho romantic"}
    ]$$)
  ) as v(order_index, prompt, options)
 where q.slug = 'style-dna'
on conflict (quiz_id, order_index) do nothing;

insert into public.feature_flags (key, enabled, description)
values ('feature_style_quiz', false, 'Home: Style DNA quiz')
on conflict (key) do nothing;
