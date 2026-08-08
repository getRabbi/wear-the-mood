-- ============================================================================
-- 0055 — Affiliate redirect configuration and click tracking
--        (DISCOVER spec §17.7, §18, §38)
--
-- ADDITIVE + IDEMPOTENT. Two new tables; nothing existing is altered. Every
-- endpoint that reads them is behind `feature_shopping`, which is FALSE, so
-- applying this changes no user-visible behaviour.
--
-- THE SECURITY BOUNDARY OF THIS MIGRATION: `merchants` is read-public, so the
-- affiliate URL template and the tracking tag CANNOT live there — that is
-- confidential commercial configuration and §17 forbids exposing it to the
-- client. It lives in `merchant_affiliate_config`, which has RLS ON and NO
-- POLICIES AT ALL. That is not an oversight: with RLS enabled and no policy,
-- anon and authenticated read exactly zero rows, while the backend's own
-- service-role connection is unaffected. The redirect service is the only
-- thing that ever sees a destination URL.
-- ============================================================================

-- ── merchant_affiliate_config ───────────────────────────────────────────────
-- How a merchant's opaque `products.affiliate_ref` becomes a real destination.

create table if not exists public.merchant_affiliate_config (
  merchant_id   uuid primary key references public.merchants (id) on delete cascade,

  -- An absolute https URL containing `{ref}`, and optionally `{tag}`. The
  -- product's affiliate_ref is substituted PERCENT-ENCODED, so a hostile or
  -- malformed ref cannot break out of the path/query and point somewhere else
  -- — the host always comes from this template, never from row data (§38).
  -- Null means this merchant's refs are already absolute URLs, which are then
  -- validated against `merchants.allowed_domains` exactly the same way.
  url_template  text,

  -- The affiliate network's tracking parameter value. A SECRET: it identifies
  -- the account that gets paid. Never returned by any endpoint and never
  -- logged (§40 "logs must not contain affiliate secrets").
  affiliate_tag text,

  -- Which parameter name carries the tag when it is appended to an absolute
  -- ref, e.g. `tag`, `aff_id`, `utm_source`.
  tag_param     text not null default 'tag',

  -- `ok` | `paused` | `revoked`. Anything other than `ok` suppresses the
  -- redirect: an expired affiliate agreement must stop earning clicks rather
  -- than keep sending users out under a dead tag.
  status        text not null default 'ok',

  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- RLS on, deliberately no policies: default-deny for anon and authenticated.
alter table public.merchant_affiliate_config enable row level security;

-- ── affiliate_clicks ────────────────────────────────────────────────────────
-- One row per outbound click (§17.7). Created SERVER-SIDE only — there is no
-- insert policy, because a click the client could write is a click the client
-- could fabricate, and these rows are what commission reconciliation is
-- checked against (§17 "affiliate click creation must be validated
-- server-side").

create table if not exists public.affiliate_clicks (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles (id) on delete cascade,
  product_id          uuid references public.products (id) on delete set null,
  merchant_id         uuid references public.merchants (id) on delete set null,

  tracking_token      text,
  -- Where the click came from: feed_grid | product_details | story_rail |
  -- search | saved | complete_look. A typed code, never display text.
  feed_placement      text,
  story_id            text,
  campaign_id         text,

  -- Whether this user had already generated a try-on for this product when the
  -- click happened. DERIVED server-side from product_interactions, never taken
  -- from the client — it is a conversion metric, and §38 says not to trust
  -- client-supplied values (§13 "track whether an affiliate click occurred
  -- after Try-On").
  try_on_completed    boolean not null default false,

  -- A REFERENCE, not the tagged URL. Storing the fully built destination would
  -- put the affiliate tag — a secret — in a table, so only the merchant-side
  -- product reference and the host that was actually opened are kept. That is
  -- enough to reconcile a conversion and to audit which domain a user was sent
  -- to; it is not enough to leak the account that gets paid.
  destination_ref     text,
  destination_host    text,

  country             char(2),
  clicked_at          timestamptz not null default now(),

  -- Stable across retries of the SAME tap. The partial unique index below is
  -- what makes a retry a no-op rather than a second click.
  client_event_key    text,

  -- Filled in later by conversion import: pending | confirmed | rejected.
  conversion_status   text not null default 'pending',
  commission_minor    bigint check (commission_minor >= 0),
  commission_currency char(3),
  updated_at          timestamptz not null default now()
);

-- Idempotency at the row level, on top of the Idempotency-Key store the
-- endpoint uses. Belt and braces: a retried tap must be ONE click, because a
-- duplicate inflates the click-through rate the whole funnel is judged on.
create unique index if not exists affiliate_clicks_dedupe_idx
  on public.affiliate_clicks (user_id, client_event_key)
  where client_event_key is not null;

create index if not exists affiliate_clicks_user_idx
  on public.affiliate_clicks (user_id, clicked_at desc);
create index if not exists affiliate_clicks_product_idx
  on public.affiliate_clicks (product_id, clicked_at desc);
create index if not exists affiliate_clicks_conversion_idx
  on public.affiliate_clicks (conversion_status, clicked_at desc);

alter table public.affiliate_clicks enable row level security;

drop policy if exists affiliate_clicks_select_own on public.affiliate_clicks;
-- Readable by the user it belongs to; there is deliberately no insert, update
-- or delete policy, so the only writer is the backend.
create policy affiliate_clicks_select_own on public.affiliate_clicks
  for select using (auth.uid() = user_id);
