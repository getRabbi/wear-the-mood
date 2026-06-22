-- ============================================================================
-- 0021 — Shared media_assets table  (INFRA_UPGRADE Phase 1B · COMMIT 1)
--
-- Additive + NON-DESTRUCTIVE groundwork for the Cloudflare-R2 public/private
-- image split. We introduce ONE polymorphic ledger of every image object instead
-- of bolting 9 metadata columns onto each image-bearing table — wardrobe rows
-- carry 3 images each and `giveaways.images` is an unbounded array, so per-table
-- columns can't be applied uniformly. (Approved approach, 1B-STEP-0 / option b.)
--
-- KEY DESIGN POINTS
--  * Polymorphic reference: (owner_kind, owner_id, role) points back at the
--    parent row. NO foreign keys on owner_id / user_id — this table is the
--    DELETION LEDGER and MUST survive the `auth.users` → `profiles` cascade
--    (see backend/app/routers/v1/account.py). If it cascaded, we'd lose the
--    object_keys needed to delete the underlying R2 objects in Phase 4A and
--    leak orphaned files. Ownership is enforced by the backend (service-role)
--    + RLS below, exactly as we already accept for owner_id being generic.
--  * `visibility` = the POLICY/target (public|private), from the approved
--    classification. `storage_provider` = where the bytes live NOW + how to
--    serve them (legacy|r2). These are independent on purpose:
--      - During migration a private-classified asset may still be
--        storage_provider='legacy' and served from its old (public) URL. That
--        was ALREADY public before this migration — we only ever TIGHTEN, never
--        expose anything new — so the opt-in public closet never breaks
--        mid-migration (INFRA_UPGRADE point A). Reads resolve PER-RECORD by
--        storage_provider: legacy → legacy_url; r2 → public_url (public) or a
--        short-lived signed URL (private).
--  * Existing `*_url` / `storage_path` / `images` columns are LEFT UNTOUCHED
--    and copied into `legacy_url`, so resolution can always fall back and
--    rollback is a no-op (ignore media_assets; legacy columns intact).
--
-- BACKFILL (metadata only — NO bytes are moved here; the byte copy is 1C):
-- one legacy row per existing image across wardrobe / profiles / tryon_results /
-- tryon_photos / posts / giveaways, with the approved visibility.
--
-- Idempotent: `create ... if not exists` + every backfill INSERT is guarded by
-- NOT EXISTS, so this migration is safe to re-run. Do NOT touch
-- FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table
-- ----------------------------------------------------------------------------
create table if not exists public.media_assets (
  id               uuid primary key default gen_random_uuid(),

  -- Polymorphic back-reference to the parent row (no FK — see header).
  owner_kind       text not null,   -- wardrobe_item|profile|tryon_result|tryon_photo|post|giveaway|saved_look|…
  owner_id         uuid not null,
  role             text not null,   -- original|cutout|thumbnail|avatar|profile_pic|result|tryon_photo|post|giveaway|…
  user_id          uuid,            -- owning user (for the Phase 4A deletion sweep + ownership checks)

  -- Policy vs. physical location (independent — see header).
  visibility       text not null check (visibility in ('public', 'private')),
  storage_provider text not null default 'legacy'
                     check (storage_provider in ('legacy', 'r2')),

  -- R2 object pointers (filled when storage_provider flips to 'r2' in 1C/Commit 3).
  object_key       text,            -- key in the public OR private R2 bucket
  thumbnail_key    text,            -- server-generated thumbnail, same bucket as its visibility
  public_url       text,            -- public assets only (R2_PUBLIC_BASE_URL + object_key)

  -- Legacy pointer (current Supabase URL or storage path) — resolution fallback.
  legacy_url       text,

  content_hash     text,            -- set during 1C VERIFY (integrity / dedupe)
  mime_type        text,
  migrated_at      timestamptz,     -- when bytes were copied to R2 (null = still legacy)
  deleted_at       timestamptz,     -- soft delete (Phase 4A); object cleanup follows after retention

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- Indexes
-- ----------------------------------------------------------------------------
-- Resolve a parent row's images (closet grid, feed card, profile, …).
create index if not exists media_assets_owner_idx
  on public.media_assets (owner_kind, owner_id, role);
-- Phase 4A deletion / export: every object a user owns, in one scan.
create index if not exists media_assets_user_idx
  on public.media_assets (user_id);
-- 1C backfill: find rows still on the old store cheaply.
create index if not exists media_assets_legacy_idx
  on public.media_assets (storage_provider)
  where storage_provider = 'legacy' and deleted_at is null;

-- ----------------------------------------------------------------------------
-- updated_at trigger (reuses the baseline helper)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_media_assets_updated_at on public.media_assets;
create trigger trg_media_assets_updated_at
  before update on public.media_assets
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Row Level Security
--   * Writes are service-role ONLY (worker/backend) — like notifications /
--     idempotency_keys — so a client can never forge or repoint an asset.
--   * A public, non-deleted asset is world-readable (its public_url is public
--     by definition). A private asset is readable only by its owner
--     (defence-in-depth; private bytes are still gated by signed URLs).
-- ----------------------------------------------------------------------------
alter table public.media_assets enable row level security;

drop policy if exists media_assets_select_public on public.media_assets;
create policy media_assets_select_public on public.media_assets
  for select using (visibility = 'public' and deleted_at is null);

drop policy if exists media_assets_select_own on public.media_assets;
create policy media_assets_select_own on public.media_assets
  for select using (auth.uid() = user_id);
-- No insert/update/delete policy => only the service role writes.

-- ============================================================================
-- BACKFILL — one legacy metadata row per existing image (idempotent).
-- visibility per the approved classification table (1B-STEP-0).
-- NOT migrated here (documented, no rows): outfits.cover_image_url (a reference
-- to a wardrobe image, no own object); tryon_jobs.person/garment URLs (transient
-- provider inputs); news_items (external RSS hotlinks); daily_guides/offers/quiz
-- (editorial, null today); saved_look images (on-device only, no DB row).
-- ============================================================================

-- wardrobe_items → PRIVATE (F2: deliberate hardening; bucket is public today,
-- the bytes move to the private R2 bucket in 1C). Three roles per item.
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'wardrobe_item', w.id, 'original', w.user_id, 'private', 'legacy', w.image_url
  from public.wardrobe_items w
 where w.image_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'wardrobe_item' and m.owner_id = w.id
                      and m.role = 'original');

insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'wardrobe_item', w.id, 'cutout', w.user_id, 'private', 'legacy', w.cutout_url
  from public.wardrobe_items w
 where w.cutout_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'wardrobe_item' and m.owner_id = w.id
                      and m.role = 'cutout');

insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'wardrobe_item', w.id, 'thumbnail', w.user_id, 'private', 'legacy', w.thumbnail_url
  from public.wardrobe_items w
 where w.thumbnail_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'wardrobe_item' and m.owner_id = w.id
                      and m.role = 'thumbnail');

-- profiles.avatar_url → PRIVATE (validated full-body try-on photo; biometric-adjacent).
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'profile', p.id, 'avatar', p.id, 'private', 'legacy', p.avatar_url
  from public.profiles p
 where p.avatar_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'profile' and m.owner_id = p.id
                      and m.role = 'avatar');

-- profiles.profile_picture_url → PRIVATE (F1: owner-only today; not on public profile).
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'profile', p.id, 'profile_pic', p.id, 'private', 'legacy', p.profile_picture_url
  from public.profiles p
 where p.profile_picture_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'profile' and m.owner_id = p.id
                      and m.role = 'profile_pic');

-- tryon_results.result_image_url → PRIVATE (the user's body in an outfit).
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'tryon_result', r.id, 'result', r.user_id, 'private', 'legacy', r.result_image_url
  from public.tryon_results r
 where r.result_image_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'tryon_result' and m.owner_id = r.id
                      and m.role = 'result');

-- tryon_photos.storage_path → PRIVATE (full-body gallery; lives in `avatars`).
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'tryon_photo', t.id, 'tryon_photo', t.user_id, 'private', 'legacy', t.storage_path
  from public.tryon_photos t
 where t.storage_path is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'tryon_photo' and m.owner_id = t.id
                      and m.role = 'tryon_photo');

-- posts.image_url → PUBLIC (moderated UGC). NOTE F7: a post made from an outfit
-- currently stores the outfit cover's wardrobe URL; it is classified PUBLIC by
-- sector, and 1C materialises a public object for it regardless of the source.
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'post', p.id, 'post', p.user_id, 'public', 'legacy', p.image_url
  from public.posts p
 where p.image_url is not null
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'post' and m.owner_id = p.id
                      and m.role = 'post');

-- giveaways.images (jsonb array) → PUBLIC (public listings). One row per image.
insert into public.media_assets
  (owner_kind, owner_id, role, user_id, visibility, storage_provider, legacy_url)
select 'giveaway', g.id, 'giveaway', g.owner_id, 'public', 'legacy', img.value
  from public.giveaways g
  cross join lateral jsonb_array_elements_text(g.images) as img(value)
 where g.images is not null
   and jsonb_typeof(g.images) = 'array'
   and img.value is not null and img.value <> ''
   and not exists (select 1 from public.media_assets m
                    where m.owner_kind = 'giveaway' and m.owner_id = g.id
                      and m.role = 'giveaway' and m.legacy_url = img.value);

-- ============================================================================
-- End of 0021
-- ============================================================================
