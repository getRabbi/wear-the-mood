-- ============================================================================
-- 0070 — Try-on eligibility requires a KNOWN garment role (MIGRATION B)
--
-- ⚠ APPLY ONLY AFTER THE BACKFILL. This is phase B of the rollout started in
--   0069. Running it before `scripts/backfill_canonical_category.py --apply`
--   has populated `products.canonical_category` would make every catalog
--   product try-on ineligible until the backfill catches up. Order:
--
--     0069  -> deploy -> backfill --dry-run -> backfill --apply -> 0070 (here)
--
--   Rollback: re-run the 0068 definitions of `product_tryon_ready` and
--   `product_tryon_readiness` (they are unchanged apart from the one condition
--   added below). Nothing else in this file writes data.
--
-- WHAT IT CHANGES
-- ---------------
-- One more AND on the existing gate. Every condition 0065/0067/0068 imposed is
-- still here and still required; this can only make a product INELIGIBLE and can
-- never make one eligible. Rights and operator coverage are untouched and still
-- outrank everything (§28): a product is try-on ready only when the permission
-- conditions AND the technical condition both pass.
--
-- WHY IT IS A GATE AND NOT A DEFAULT
-- ----------------------------------
-- Without a canonical role the pipeline has to ask the provider to work out what
-- a garment is, and a misread turns a shirt into a full-body replacement on
-- somebody's photo — charged, and wrong. Refusing is the safe direction: the
-- product keeps every row, every image and every shopping surface, and only the
-- Try On affordance goes away until its category is known.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- The canonical categories the ACTIVE provider can actually render. Mirrors
-- `TRYON_CAPABLE_CATEGORIES` in backend/app/services/tryon/taxonomy.py; the
-- pytest `test_taxonomy_sql_parity` fails if the two drift.
create or replace function public.tryon_capable_category(c text)
returns boolean language sql immutable as $$
  select c in ('top','bottom','one_piece','outerwear','hijab_scarf',
               'glasses','hat_headwear','shoes','bag','jewelry')
$$;

comment on function public.tryon_capable_category(text) is
  'Whether a canonical garment role can be rendered by the active try-on '
  'provider. Mirrors TRYON_CAPABLE_CATEGORIES in taxonomy.py.';

grant execute on function public.tryon_capable_category(text)
  to anon, authenticated, service_role;

-- ── the gate, with the technical condition added and nothing removed ────────
create or replace function public.product_tryon_ready(p public.products)
returns boolean language sql stable as $$
  select p.try_on_status = 'ready'
     -- RIGHTS. Authoritative, and first: no operational toggle outranks it.
     and public.product_effective_image_rights(p) = 'licensed'
     -- COVERAGE. The operator's decision about whether we use that permission.
     and public.product_effective_tryon_policy(p) = 'on'
     and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
     -- ROLE. What the piece is, so the renderer is never asked to guess.
     and public.tryon_capable_category(p.canonical_category)
     and coalesce(p.classification_status, 'valid') <> 'needs_review'
$$;

comment on function public.product_tryon_ready(public.products) is
  'May this product be used as AI try-on INPUT. Requires licensed effective '
  'rights, an ON effective coverage policy, an earned ready status, a usable '
  'image, and a provider-renderable canonical garment role. The single '
  'definition every surface reads.';

-- ── readiness, explained (the console must be able to say WHY) ──────────────
create or replace function public.product_tryon_readiness(p public.products)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'effective_rights', public.product_effective_image_rights(p),
    'rights_ok',        public.product_effective_image_rights(p) = 'licensed',
    'merchant_mode',    public.merchant_tryon_mode(p.merchant_id),
    'policy_override',  p.tryon_policy_override,
    'effective_policy', public.product_effective_tryon_policy(p),
    'policy_ok',        public.product_effective_tryon_policy(p) = 'on',
    'status',           p.try_on_status,
    'status_ok',        p.try_on_status = 'ready',
    'image',            coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]),
    'image_ok',         coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null,
    'canonical_category',    p.canonical_category,
    'classification_status', p.classification_status,
    'category_ok',      public.tryon_capable_category(p.canonical_category)
                          and coalesce(p.classification_status, 'valid') <> 'needs_review',
    'active_ok',        p.active,
    'servable',         public.product_is_servable(p),
    'ready',            public.product_tryon_ready(p),
    -- The FIRST thing standing in the way, in the order an operator would fix
    -- them: rights are the question that has to be answered before the others
    -- are worth asking. Null when it is ready.
    'blocked_by', case
      when public.product_tryon_ready(p) then null
      when public.product_effective_image_rights(p) = 'restricted' then 'rights_restricted'
      when public.product_effective_image_rights(p) <> 'licensed' then 'rights_not_licensed'
      when public.merchant_tryon_mode(p.merchant_id) = 'off' then 'merchant_tryon_off'
      when p.tryon_policy_override = 'off' then 'product_tryon_off'
      when public.product_effective_tryon_policy(p) = 'off' then 'product_not_selected'
      when coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is null then 'no_image'
      when p.canonical_category is null then 'category_unknown'
      when coalesce(p.classification_status, 'valid') = 'needs_review' then 'category_needs_review'
      when not public.tryon_capable_category(p.canonical_category) then 'category_unsupported'
      when p.try_on_status = 'pending' then 'status_pending'
      else 'status_not_ready'
    end
  )
$$;

grant execute on function public.product_tryon_readiness(public.products)
  to service_role;
