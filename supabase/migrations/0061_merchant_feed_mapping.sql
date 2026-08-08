-- ============================================================================
-- 0061 — Per-merchant feed field mapping
--
-- ADDITIVE + IDEMPOTENT. Found by pointing the importer at a REAL feed for the
-- first time: every record was skipped, and correctly so.
--
-- The normalizer expects a canonical shape (`external_id`, `title`,
-- `price_minor`, `currency`, …). No real merchant publishes that shape. A live
-- feed hands back `id` as an integer, `price` as a FLOAT in major units, no
-- currency field at all, and stock as a COUNT rather than a status — so the
-- normalizer refused all of it, which is what it is supposed to do with data it
-- cannot represent.
--
-- The fix is not to loosen the normalizer. Its strictness is the reason a
-- price cannot silently drift by a factor of 100. The fix is to let each
-- merchant DECLARE how its feed maps onto the canonical shape, so the
-- conversion is a recorded contract rather than a guess:
--
--   * `field_map`      — canonical field -> source key (dotted paths allowed)
--   * `price_format`   — 'minor' (default, unchanged) | 'major'
--   * `default_currency` — for feeds that carry none
--   * `stock_map`      — value translation, and the threshold for a stock COUNT
--
-- Every default preserves today's behaviour exactly: an empty field_map with
-- price_format 'minor' is the identity mapping, so nothing already configured
-- changes.
-- ============================================================================

alter table public.merchant_feed_config
  -- Canonical -> source. `{"external_id": "id", "price_minor": "price"}`.
  -- A dotted value reads nested JSON: `"image_urls": "media.gallery"`.
  -- Absent keys fall back to the canonical name, so a feed that already speaks
  -- our shape needs no map at all.
  add column if not exists field_map jsonb not null default '{}'::jsonb,

  -- How the mapped price is denominated.
  --
  -- 'minor' means the feed already sends integer minor units and nothing is
  -- converted — the existing, safest behaviour, and still the default.
  --
  -- 'major' means the feed sends a human price (9.99) and the importer scales
  -- it by the currency's exponent. This is the ONE place a float is accepted,
  -- and only because an operator has declared what it means; the conversion is
  -- done in decimal, never binary float, so 9.99 becomes exactly 999.
  add column if not exists price_format text not null default 'minor'
    check (price_format in ('minor', 'major')),

  -- ISO-4217 for feeds that omit it. Without this such a feed is unimportable,
  -- because a price with no currency is not a price.
  add column if not exists default_currency char(3),

  -- Optional stock translation:
  --   {"values": {"available": "in_stock", "sold out": "out_of_stock"},
  --    "low_stock_at": 5}
  -- `low_stock_at` turns a numeric count into a status: 0 is out_of_stock, at
  -- or below the threshold is low_stock, above it is in_stock.
  add column if not exists stock_map jsonb not null default '{}'::jsonb;

comment on column public.merchant_feed_config.field_map is
  'Canonical field -> source key. Dotted paths read nested JSON. Empty = identity.';
comment on column public.merchant_feed_config.price_format is
  'minor = integer minor units as-is; major = human price scaled by the currency exponent.';
