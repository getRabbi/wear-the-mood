-- ============================================================================
-- 0018 — Daily Guide (FEATURES_COMMUNITY_PLUS · Daily Guide)
--
-- A daily editorial styling guide for the Home "Today" section — the daily-habit
-- hook. Curated content (read-public); the backend serves the latest guide on or
-- before today. Seeds a couple of guides + feature_daily_guide (OFF, §16).
-- Idempotent: unique (date, title) + on conflict do nothing. Do NOT touch
-- FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

create table if not exists public.daily_guides (
  id         uuid primary key default gen_random_uuid(),
  date       date not null,
  title      text not null,
  summary    text,
  body       text,
  image_url  text,
  topics     jsonb not null default '[]'::jsonb,   -- ["layering", ...]
  cta        jsonb not null default '[]'::jsonb,   -- [{label, action, target?}]
  created_at timestamptz not null default now(),
  unique (date, title)
);

create index if not exists daily_guides_date_idx on public.daily_guides (date desc);

alter table public.daily_guides enable row level security;

-- Editorial content is public read; writes are service-role (curation/cron).
drop policy if exists daily_guides_select_public on public.daily_guides;
create policy daily_guides_select_public on public.daily_guides
  for select using (true);

-- ── Seed a couple of guides (dates relative to apply time) ──────────────────
insert into public.daily_guides (date, title, summary, body, topics, cta)
values
  (current_date, 'Transitional layering',
   'Lightweight layers for changeable weather — here''s how to make them work.',
   $$When the forecast can''t make up its mind, layering is your friend. Start with a breathable base, add a mid-layer you can shed by midday, and finish with one considered topper. Keep the palette tight so the layers read as one outfit, not three. Roll sleeves, leave a jacket open, and let texture — knit over cotton over denim — do the talking.$$,
   $$["layering","transitional","outerwear"]$$::jsonb,
   $$[{"label":"Build a look","action":"tryon"},{"label":"Check your closet","action":"closet"}]$$::jsonb),
  (current_date - 1, 'The one-colour outfit',
   'Monochrome dressing, done right.',
   $$Dressing head-to-toe in a single colour looks intentional and elongating. Play with shades and textures within one family — ecru, cream and oat — so the look has depth without breaking the line. Add a single contrasting accessory if you want a focal point.$$,
   $$["monochrome","minimal"]$$::jsonb,
   $$[{"label":"Open your closet","action":"closet"}]$$::jsonb)
on conflict (date, title) do nothing;

insert into public.feature_flags (key, enabled, description)
values ('feature_daily_guide', false, 'Home: daily "Today" styling guide')
on conflict (key) do nothing;
