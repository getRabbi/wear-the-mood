-- ============================================================================
-- 0020 — Giveaways (FEATURES_COMMUNITY_PLUS · Giveaway)
--
-- Peer-to-peer "give away clothes for free". HIGH safety surface:
--   * listings are public (read-public) but writes are owner-only;
--   * images + text are moderated by the backend before publish (§19);
--   * NO personal address/phone in public listings — contact is in-app via a
--     private claim message (claimer ↔ owner), never exposed publicly (§10);
--   * a claim is one-per-user (unique) and the owner accepts/declines.
-- Seeds feature_giveaway (OFF, §16). Idempotent. Do NOT touch the baseline (§6).
-- ============================================================================

create table if not exists public.giveaways (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null references public.profiles (id) on delete cascade,
  wardrobe_item_id uuid references public.wardrobe_items (id) on delete set null,
  title            text not null,
  description      text,
  images           jsonb not null default '[]'::jsonb,   -- [url, ...]
  size             text,
  category         text,
  condition        text,
  area_label       text,                                 -- coarse area only, never an address
  status           text not null default 'available'
                     check (status in ('available','reserved','claimed','closed')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists giveaways_status_idx on public.giveaways (status, created_at desc);
create index if not exists giveaways_owner_idx on public.giveaways (owner_id);

create table if not exists public.giveaway_claims (
  id          uuid primary key default gen_random_uuid(),
  giveaway_id uuid not null references public.giveaways (id) on delete cascade,
  claimer_id  uuid not null references public.profiles (id) on delete cascade,
  message     text,
  status      text not null default 'requested'
                check (status in ('requested','accepted','declined')),
  created_at  timestamptz not null default now(),
  unique (giveaway_id, claimer_id)              -- one claim per user per giveaway
);

create index if not exists giveaway_claims_giveaway_idx on public.giveaway_claims (giveaway_id);
create index if not exists giveaway_claims_claimer_idx on public.giveaway_claims (claimer_id);

alter table public.giveaways      enable row level security;
alter table public.giveaway_claims enable row level security;

-- giveaways: public browse; write-own (backend runs service-role).
drop policy if exists giveaways_select_public on public.giveaways;
create policy giveaways_select_public on public.giveaways for select using (true);
drop policy if exists giveaways_write_own on public.giveaways;
create policy giveaways_write_own on public.giveaways
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

-- claims: a claimer reads/creates their OWN claim; the giveaway owner can read +
-- update (accept/decline) claims on their listing. No public read of who claimed.
drop policy if exists giveaway_claims_select_own_or_owner on public.giveaway_claims;
create policy giveaway_claims_select_own_or_owner on public.giveaway_claims
  for select using (
    auth.uid() = claimer_id
    or auth.uid() = (select g.owner_id from public.giveaways g where g.id = giveaway_id)
  );
drop policy if exists giveaway_claims_insert_own on public.giveaway_claims;
create policy giveaway_claims_insert_own on public.giveaway_claims
  for insert with check (auth.uid() = claimer_id);
drop policy if exists giveaway_claims_update_owner on public.giveaway_claims;
create policy giveaway_claims_update_owner on public.giveaway_claims
  for update using (
    auth.uid() = (select g.owner_id from public.giveaways g where g.id = giveaway_id)
  );

insert into public.feature_flags (key, enabled, description)
values ('feature_giveaway', false, 'Community: give away clothes for free (P2P)')
on conflict (key) do nothing;
