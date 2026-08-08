-- ============================================================================
-- 0056 — Shopping origin on a try-on job (DISCOVER spec §13, §36)
--
-- ADDITIVE + IDEMPOTENT. Five nullable columns on an existing table and one
-- partial index. Every existing row keeps NULL, which means "a closet render"
-- — the shape older clients and older results already have, so nothing has to
-- be back-filled and nothing changes for them.
--
-- WHY THE JOB AND NOT A LOCAL FILE: a render outlives the screen that started
-- it. The app can be killed while the worker finishes, and the user can reopen
-- the result days later from Saved Looks. Origin kept only in memory is origin
-- lost exactly when someone comes back to buy — which is the moment the whole
-- feature exists for.
--
-- WHAT IS DELIBERATELY NOT HERE: no affiliate URL, no affiliate tag, no
-- merchant redirect configuration, and NO PRICE. A price stored here would be
-- a purchase claim nobody re-verified — §35 is explicit that a stale price must
-- not be shown as current, so the restore path re-reads it through the Phase 4
-- product endpoint instead of trusting anything cached on the job.
-- ============================================================================

alter table public.tryon_jobs
  -- 'affiliate_product' | null. A discriminator rather than a bare id so a
  -- future source (a shared look, a challenge) does not have to guess.
  add column if not exists source_kind text,
  -- ON DELETE SET NULL, not CASCADE: a product being withdrawn from the catalog
  -- must never delete somebody's render. The job survives, loses its origin,
  -- and the result reopens as an ordinary look.
  add column if not exists source_product_id uuid
    references public.products (id) on delete set null,
  add column if not exists source_merchant_id uuid
    references public.merchants (id) on delete set null,
  -- Where the try-on was started from: feed_grid | product_details | search |
  -- saved. A typed code, carried so the funnel can attribute the render.
  add column if not exists source_placement text,
  add column if not exists source_campaign_id text;

-- Only the shopping renders. A partial index because the overwhelming majority
-- of rows are closet try-ons and have nothing to index.
create index if not exists tryon_jobs_source_product_idx
  on public.tryon_jobs (source_product_id, created_at desc)
  where source_product_id is not null;
