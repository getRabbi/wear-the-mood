-- ============================================================================
-- 0033 — Premium AI Studio foundation (BUILD_PROMPT_PRO_PROMAX.md)
--
-- Shared AI-job system for the premium, credit-gated AI features:
--   * enhance_item       — make a closet piece clean / catalog-ready (Pro/Pro Max)
--   * catalog_model      — show a piece on an AI fashion model (Pro/Pro Max)
--   * tryon_*            — reserved values; try-on itself stays on tryon_jobs
--                          (own_photo + studio_model). See model_source below.
--
-- DESIGN (founder-approved 2026-06-30):
--   * own_photo + studio_model TRY-ON reuse the existing, proven tryon_jobs
--     pipeline — this migration only ADDS tryon_jobs.model_source + preset_model_id.
--   * ai_jobs + generated_images are NEW and cover ONLY enhance_item +
--     catalog_model, mirroring the tryon_jobs reserve-at-submit / refund-on-fail
--     credit pattern (credits_reserved/credits_charged are audit columns; the
--     authoritative ledger stays credit_transactions).
--   * tryon_model_presets seeds 5 studio models is_active=false with a NULL
--     image_url — INERT until the founder uploads real R2/CDN images and flips
--     is_active, so nothing broken ever ships.
--   * tryon_avatars is FUTURE-READY only (My Style Model) — schema + RLS now, no
--     generation built.
--
-- Additive, idempotent, re-runnable. Apply to DEV first, verify, then prod.
-- Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- tryon_model_presets — curated studio / catalog model images
-- ----------------------------------------------------------------------------
create table if not exists public.tryon_model_presets (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null default 'studio_tryon'
                check (kind in ('studio_tryon', 'catalog')),
  name        text not null,
  image_url   text,                          -- hosted R2/CDN full-body model image
  style       text,                          -- machine key (female_studio, modest, …)
  body_type   text,
  skin_tone   text,
  pose_type   text,
  is_active   boolean not null default false, -- only active presets are shown / usable
  is_pro_only boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists tryon_model_presets_active_idx
  on public.tryon_model_presets (kind, sort_order)
  where is_active = true;

-- ----------------------------------------------------------------------------
-- ai_jobs — shared async job for enhance_item / catalog_model (CLAUDE.md §7)
-- ----------------------------------------------------------------------------
create table if not exists public.ai_jobs (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles (id) on delete cascade,
  job_type         text not null
                     check (job_type in ('enhance_item', 'catalog_model',
                                         'tryon_own_photo', 'tryon_studio_model')),
  status           text not null default 'queued'
                     check (status in ('queued', 'processing', 'completed', 'failed')),
  input_urls       text[] not null default '{}',
  output_urls      text[] not null default '{}',
  provider         text,
  provider_job_id  text,
  source_item_id   uuid references public.wardrobe_items (id) on delete set null,
  preset_model_id  uuid references public.tryon_model_presets (id) on delete set null,
  style            text,
  quality          text not null default 'standard'
                     check (quality in ('standard', 'pro_max')),
  hd               boolean not null default false,
  credits_reserved integer not null default 0,
  credits_charged  integer not null default 0,
  idempotency_key  text,
  error_message    text,
  created_at       timestamptz not null default now(),
  completed_at     timestamptz
);
create index if not exists ai_jobs_user_idx on public.ai_jobs (user_id);
create index if not exists ai_jobs_queued_idx on public.ai_jobs (created_at)
  where status = 'queued';

-- ----------------------------------------------------------------------------
-- generated_images — AI outputs (enhanced item / catalog shot / tryon result)
-- ----------------------------------------------------------------------------
create table if not exists public.generated_images (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  source_item_id  uuid references public.wardrobe_items (id) on delete set null,
  job_id          uuid references public.ai_jobs (id) on delete set null,
  type            text not null
                    check (type in ('enhanced_item', 'catalog_model', 'tryon_result')),
  output_url      text,                       -- R2 object_key (signed on serve) or http url
  is_ai_generated boolean not null default true,
  report_count    integer not null default 0,
  created_at      timestamptz not null default now()
);
create index if not exists generated_images_user_idx on public.generated_images (user_id);
create index if not exists generated_images_item_idx on public.generated_images (source_item_id);

-- ----------------------------------------------------------------------------
-- tryon_avatars — FUTURE-READY (My Style Model). Schema + RLS only; no generation.
-- ----------------------------------------------------------------------------
create table if not exists public.tryon_avatars (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,
  name               text,
  avatar_image_url   text,
  thumbnail_url      text,
  source_photo_url   text,
  face_reference_url text,
  skin_tone          text,
  body_type          text,
  status             text not null default 'draft'
                       check (status in ('draft', 'processing', 'ready', 'failed')),
  is_default         boolean not null default false,
  created_at         timestamptz not null default now()
);
create index if not exists tryon_avatars_user_idx on public.tryon_avatars (user_id);

-- ----------------------------------------------------------------------------
-- wardrobe_items — AI enhance columns (additive; existing image_url = original,
-- cutout_url = cutout are reused, so we add only the NEW fields).
-- ----------------------------------------------------------------------------
alter table public.wardrobe_items
  add column if not exists enhanced_image_url text,
  add column if not exists cover_image_url    text,
  add column if not exists ai_enhanced        boolean not null default false,
  add column if not exists ai_status          text
    check (ai_status in ('queued', 'processing', 'done', 'failed')),
  add column if not exists source_type        text;  -- user_upload | seed | import

-- ----------------------------------------------------------------------------
-- tryon_jobs — the Try-On Body System (own_photo | studio_model | user_avatar).
-- model_source defaults to own_photo, so EVERY existing + future own-photo job is
-- unchanged. studio_model carries the chosen preset.
-- ----------------------------------------------------------------------------
alter table public.tryon_jobs
  add column if not exists model_source text not null default 'own_photo'
    check (model_source in ('own_photo', 'studio_model', 'user_avatar')),
  add column if not exists preset_model_id uuid
    references public.tryon_model_presets (id) on delete set null;

-- ----------------------------------------------------------------------------
-- Row Level Security
--   * ai_jobs            — read OWN; writes are service-role only (the worker).
--   * generated_images   — read / update / delete OWN; insert service-role only.
--   * tryon_model_presets— ACTIVE presets readable by any authed user; writes svc.
--   * tryon_avatars      — own-row all (defence-in-depth; backend is service-role).
-- ----------------------------------------------------------------------------
alter table public.ai_jobs              enable row level security;
alter table public.generated_images    enable row level security;
alter table public.tryon_model_presets enable row level security;
alter table public.tryon_avatars       enable row level security;

drop policy if exists ai_jobs_select_own on public.ai_jobs;
create policy ai_jobs_select_own on public.ai_jobs
  for select using (auth.uid() = user_id);
-- No insert/update/delete policy => only the service role writes.

drop policy if exists generated_images_select_own on public.generated_images;
create policy generated_images_select_own on public.generated_images
  for select using (auth.uid() = user_id);
drop policy if exists generated_images_update_own on public.generated_images;
create policy generated_images_update_own on public.generated_images
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists generated_images_delete_own on public.generated_images;
create policy generated_images_delete_own on public.generated_images
  for delete using (auth.uid() = user_id);
-- Insert is service-role only (the worker records outputs).

drop policy if exists tryon_model_presets_select_active on public.tryon_model_presets;
create policy tryon_model_presets_select_active on public.tryon_model_presets
  for select using (is_active = true and auth.uid() is not null);
-- No write policy => only the service role seeds / toggles presets.

drop policy if exists tryon_avatars_rw_own on public.tryon_avatars;
create policy tryon_avatars_rw_own on public.tryon_avatars
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- Seed the 5 initial studio models — INACTIVE + NULL image_url. The founder
-- uploads real full-body R2/CDN images, sets image_url and flips is_active=true;
-- the picker shows only active presets, so studio-model try-on stays hidden until
-- then. Idempotent (guarded on style).
-- ----------------------------------------------------------------------------
insert into public.tryon_model_presets
  (kind, name, style, body_type, skin_tone, pose_type, is_active, is_pro_only, sort_order)
select v.kind, v.name, v.style, v.body_type, v.skin_tone, v.pose_type, false, true, v.sort_order
from (values
  ('studio_tryon', 'Female Studio',     'female_studio', 'average', 'medium',  'front_full', 1),
  ('studio_tryon', 'Modest Model',      'modest',        'average', 'medium',  'front_full', 2),
  ('studio_tryon', 'Male Studio',       'male_studio',   'average', 'medium',  'front_full', 3),
  ('studio_tryon', 'Curve Model',       'curve',         'curvy',   'medium',  'front_full', 4),
  ('studio_tryon', 'Neutral Full Body', 'neutral',       'average', 'neutral', 'front_full', 5)
) as v(kind, name, style, body_type, skin_tone, pose_type, sort_order)
where not exists (
  select 1 from public.tryon_model_presets p
   where p.kind = 'studio_tryon' and p.style = v.style
);

-- ============================================================================
-- End of 0033
-- ============================================================================
