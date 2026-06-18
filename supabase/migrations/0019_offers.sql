-- ============================================================================
-- 0019 — Daily Offers (FEATURES_COMMUNITY_PLUS · Daily Offer)
--
-- Curated/affiliate deals for the Newsroom "Offers" strip — deliberately OUT of
-- the social feed to protect trust. Read-public content; the backend serves the
-- active, in-window offers and appends affiliate attribution at serve time (§18,
-- no PII). Seeds a couple of offers + feature_daily_offers (OFF, §16).
-- Idempotent: unique (title, affiliate_url) + on conflict do nothing. Do NOT
-- touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

create table if not exists public.offers (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  brand          text,
  image_url      text,
  discount_label text,
  affiliate_url  text not null,
  valid_from     timestamptz,
  valid_to       timestamptz,
  topics         jsonb not null default '[]'::jsonb,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (title, affiliate_url)
);

create index if not exists offers_active_idx
  on public.offers (is_active, valid_to);

alter table public.offers enable row level security;

-- Offers are public content (read-public); writes are service-role (curation).
drop policy if exists offers_select_public on public.offers;
create policy offers_select_public on public.offers for select using (true);

insert into public.offers
  (title, brand, image_url, discount_label, affiliate_url, valid_to, topics)
values
  ('Up to 40% off knitwear', 'Studio Label', null, '-40%',
   'https://example.com/shop/knitwear', now() + interval '14 days',
   $$["knitwear","sale"]$$::jsonb),
  ('New-season denim', 'Denim Co.', null, 'New in',
   'https://example.com/shop/denim', now() + interval '30 days',
   $$["denim"]$$::jsonb)
on conflict (title, affiliate_url) do nothing;

insert into public.feature_flags (key, enabled, description)
values ('feature_daily_offers', false, 'Newsroom: daily affiliate offers strip')
on conflict (key) do nothing;
