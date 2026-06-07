-- ============================================================================
-- Fashion OS — Supabase baseline schema (CLAUDE.md §5)
-- Canonical baseline. Later changes go in supabase/migrations/NNNN_*.sql.
-- Idempotent: safe to re-run. RLS ON for every user-owned table.
-- Apply via the Supabase SQL editor (recommended) or psql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------
create extension if not exists pgcrypto;   -- gen_random_uuid()
create extension if not exists vector;      -- pgvector (embeddings)

-- Embedding dimension = OpenAI text-embedding-3-small (CLAUDE.md §2.1).
-- If you change the embedding model, change the vector() size everywhere.

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- Core user tables (own-row RLS)
-- ============================================================================

-- profiles -------------------------------------------------------------------
create table if not exists public.profiles (
  id                   uuid primary key references auth.users (id) on delete cascade,
  username             text unique,
  display_name         text,
  avatar_url           text,
  body_data            jsonb,            -- height/measurements (sensitive, §10)
  timezone             text,             -- for per-timezone daily push (§20)
  onboarding_completed boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- credits --------------------------------------------------------------------
create table if not exists public.credits (
  user_id         uuid primary key references public.profiles (id) on delete cascade,
  balance         integer not null default 0,
  daily_free_used integer not null default 0,
  daily_reset_on  date not null default current_date,
  updated_at      timestamptz not null default now()
);

-- wardrobe_items -------------------------------------------------------------
create table if not exists public.wardrobe_items (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  title         text,
  category      text,
  subcategory   text,
  color         text,
  pattern       text,
  brand         text,
  image_url     text,
  cutout_url    text,
  thumbnail_url text,
  tags          text[] not null default '{}',
  embedding     vector(1536),
  cost          numeric(10, 2),
  purchase_date date,
  last_worn_at  timestamptz,
  wear_count    integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists wardrobe_items_user_idx on public.wardrobe_items (user_id);
create index if not exists wardrobe_items_embedding_idx
  on public.wardrobe_items using hnsw (embedding vector_cosine_ops);

-- outfits --------------------------------------------------------------------
create table if not exists public.outfits (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  name            text,
  item_ids        uuid[] not null default '{}',
  cover_image_url text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists outfits_user_idx on public.outfits (user_id);

-- tryon_jobs (async, §7) -----------------------------------------------------
create table if not exists public.tryon_jobs (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles (id) on delete cascade,
  status            text not null default 'queued'
                      check (status in ('queued', 'processing', 'done', 'failed')),
  person_image_url  text,
  garment_image_url text,
  wardrobe_item_id  uuid references public.wardrobe_items (id) on delete set null,
  provider          text,
  idempotency_key   text,
  error             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists tryon_jobs_user_idx on public.tryon_jobs (user_id);
create index if not exists tryon_jobs_status_idx on public.tryon_jobs (status);

-- tryon_results --------------------------------------------------------------
create table if not exists public.tryon_results (
  id               uuid primary key default gen_random_uuid(),
  job_id           uuid not null references public.tryon_jobs (id) on delete cascade,
  user_id          uuid not null references public.profiles (id) on delete cascade,
  result_image_url text,
  created_at       timestamptz not null default now()
);
create index if not exists tryon_results_user_idx on public.tryon_results (user_id);

-- taste_signals (taste graph, §24) ------------------------------------------
create table if not exists public.taste_signals (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  signal_type  text not null,           -- like | save | wear | skip | ...
  subject_type text,                    -- post | wardrobe_item | news | ...
  subject_id   uuid,
  embedding    vector(1536),
  weight       real not null default 1,
  created_at   timestamptz not null default now()
);
create index if not exists taste_signals_user_idx on public.taste_signals (user_id);
create index if not exists taste_signals_embedding_idx
  on public.taste_signals using hnsw (embedding vector_cosine_ops);

-- consents (biometric/legal, §10) -------------------------------------------
create table if not exists public.consents (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles (id) on delete cascade,
  consent_type text not null,           -- biometric | tos | privacy
  version      text not null,
  granted      boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists consents_user_idx on public.consents (user_id);

-- ============================================================================
-- Social tables (read-public, write-own)
-- ============================================================================

create table if not exists public.posts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles (id) on delete cascade,
  caption       text,
  image_url     text,
  outfit_id     uuid references public.outfits (id) on delete set null,
  visibility    text not null default 'public',
  like_count    integer not null default 0,
  comment_count integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists posts_user_idx on public.posts (user_id);
create index if not exists posts_created_idx on public.posts (created_at desc);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

create table if not exists public.likes (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  post_id    uuid not null references public.posts (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references public.posts (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);
create index if not exists comments_post_idx on public.comments (post_id);

-- reports (UGC moderation, §19) ---------------------------------------------
create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references public.profiles (id) on delete cascade,
  subject_type text not null,           -- post | comment | user
  subject_id   uuid not null,
  reason       text,
  status       text not null default 'open',
  created_at   timestamptz not null default now()
);

-- ============================================================================
-- Public-read reference tables
-- ============================================================================

create table if not exists public.news_items (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  summary      text,
  source       text,
  url          text,
  image_url    text,
  published_at timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists news_items_published_idx on public.news_items (published_at desc);

create table if not exists public.feature_flags (
  key         text primary key,
  enabled     boolean not null default false,
  description text,
  rollout     jsonb,
  updated_at  timestamptz not null default now()
);

-- ============================================================================
-- Service-role-only tables (no RLS policies => only service role can access)
-- ============================================================================

create table if not exists public.idempotency_keys (
  key         text primary key,
  user_id     uuid,
  endpoint    text,
  status_code integer,
  response    jsonb,
  created_at  timestamptz not null default now()
);

create table if not exists public.ai_usage_log (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid,
  provider      text,
  model         text,
  task          text,
  input_tokens  integer,
  output_tokens integer,
  images        integer,
  estimated_usd numeric(10, 5),
  latency_ms    integer,
  success       boolean,
  created_at    timestamptz not null default now()
);
create index if not exists ai_usage_log_created_idx on public.ai_usage_log (created_at desc);

-- ============================================================================
-- updated_at triggers
-- ============================================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'credits', 'wardrobe_items', 'outfits', 'tryon_jobs', 'posts', 'feature_flags'
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
-- Auto-provision profile + credits on signup
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  insert into public.credits (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table public.profiles        enable row level security;
alter table public.credits         enable row level security;
alter table public.wardrobe_items  enable row level security;
alter table public.outfits         enable row level security;
alter table public.tryon_jobs      enable row level security;
alter table public.tryon_results   enable row level security;
alter table public.taste_signals   enable row level security;
alter table public.consents        enable row level security;
alter table public.posts           enable row level security;
alter table public.follows         enable row level security;
alter table public.likes           enable row level security;
alter table public.comments        enable row level security;
alter table public.reports         enable row level security;
alter table public.news_items      enable row level security;
alter table public.feature_flags   enable row level security;
alter table public.idempotency_keys enable row level security;
alter table public.ai_usage_log    enable row level security;

-- profiles: own-row (CLAUDE.md §5). A limited public-read view for social can
-- be added in Phase 2 if needed.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (auth.uid() = id);
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert with check (auth.uid() = id);
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Own-row tables keyed by user_id: select/insert/update/delete own.
do $$
declare
  t text;
begin
  foreach t in array array[
    'credits', 'wardrobe_items', 'outfits', 'tryon_jobs', 'tryon_results',
    'taste_signals', 'consents'
  ]
  loop
    execute format('drop policy if exists %1$s_rw_own on public.%1$s;', t);
    execute format(
      'create policy %1$s_rw_own on public.%1$s
         for all using (auth.uid() = user_id) with check (auth.uid() = user_id);', t);
  end loop;
end;
$$;

-- posts: read-public, write-own.
drop policy if exists posts_select_public on public.posts;
create policy posts_select_public on public.posts for select using (true);
drop policy if exists posts_write_own on public.posts;
create policy posts_write_own on public.posts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- likes / comments: read-public, write-own.
drop policy if exists likes_select_public on public.likes;
create policy likes_select_public on public.likes for select using (true);
drop policy if exists likes_write_own on public.likes;
create policy likes_write_own on public.likes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists comments_select_public on public.comments;
create policy comments_select_public on public.comments for select using (true);
drop policy if exists comments_write_own on public.comments;
create policy comments_write_own on public.comments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- follows: read-public, write-own (the follower).
drop policy if exists follows_select_public on public.follows;
create policy follows_select_public on public.follows for select using (true);
drop policy if exists follows_write_own on public.follows;
create policy follows_write_own on public.follows
  for all using (auth.uid() = follower_id) with check (auth.uid() = follower_id);

-- reports: a user can file and see their own reports; moderation via service role.
drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
  for insert with check (auth.uid() = reporter_id);
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
  for select using (auth.uid() = reporter_id);

-- news_items / feature_flags: public read; writes via service role only.
drop policy if exists news_items_select_public on public.news_items;
create policy news_items_select_public on public.news_items for select using (true);
drop policy if exists feature_flags_select_public on public.feature_flags;
create policy feature_flags_select_public on public.feature_flags for select using (true);

-- idempotency_keys / ai_usage_log: RLS enabled with NO policies => only the
-- service role (which bypasses RLS) can read/write them (CLAUDE.md §5).

-- ============================================================================
-- End of baseline
-- ============================================================================
