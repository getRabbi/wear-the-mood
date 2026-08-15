-- ============================================================================
-- 0069 — Try Look execution plan + canonical garment category (MIGRATION A)
--
-- Phase A of a phased rollout (spec Phase 25). This migration is ADDITIVE ONLY:
-- every column is nullable, no existing column changes type or nullability, no
-- data is rewritten, and no gate becomes stricter. Deploying it changes nothing
-- observable on its own — which is the point. The order is:
--
--   A (here)  add columns + indexes                → safe, reversible
--   deploy    every writer starts populating them
--   backfill  scripts/backfill_canonical_category.py --dry-run, then --apply
--   B (0070)  harden: product_tryon_ready() requires a supported category
--
-- WHY
-- ---
-- `tryon_jobs` stored a bare `text[]` of garment URLs. Nothing recorded what
-- each garment WAS, which of them the render actually applied, or why one was
-- left out — so a four-piece look that came back with one shirt was
-- indistinguishable from a successful render, both in the database and to the
-- user. These columns make the plan and its outcome a stored fact.
--
-- `canonical_category` is Wear The Mood's own vocabulary
-- (backend/app/services/tryon/taxonomy.py), deliberately NOT a provider enum:
-- top | bottom | one_piece | outerwear | hijab_scarf | glasses | hat_headwear |
-- shoes | bag | jewelry | belt | other. The free-text `category` column is left
-- exactly as it is — closet drawers, filters and the admin console all read it,
-- and this adds a parallel machine-readable field rather than reinterpreting one
-- that users and merchants have been writing into for months.
--
-- Idempotent: safe to re-run. Do NOT touch FASHIONOS_BASELINE.sql (§6).
-- ============================================================================

-- ── the plan and its accounting ──────────────────────────────────────────────
alter table public.tryon_jobs
  -- The full ordered plan as built at submit: steps (item, role, model,
  -- provider category), plus everything deliberately skipped and why. No signed
  -- URLs — a plan is a durable record and a presigned URL is an expiring
  -- credential (§11).
  add column if not exists plan jsonb,
  -- Selected -> planned -> applied is the invariant a Full Look is checked
  -- against before it may be called done. Stable item keys, not URLs: a URL is
  -- re-signed on every read and could never be compared across two rows.
  add column if not exists selected_item_keys text[],
  add column if not exists planned_item_keys  text[],
  add column if not exists applied_item_keys  text[],
  add column if not exists failed_item_keys   text[],
  add column if not exists skipped_item_keys  text[],
  -- Live progress, so a stuck job says WHICH step it is stuck on, and so the
  -- app can show "2 of 4" instead of an undifferentiated spinner.
  add column if not exists current_step integer,
  add column if not exists total_steps  integer,
  -- Per-step provider record: prediction id, status, attempts, duration. This is
  -- what makes a production failure diagnosable from a job id alone (§24).
  add column if not exists step_state jsonb,
  -- Stage latencies for this job (§14/§11). Durations and counts only.
  add column if not exists timings jsonb;

comment on column public.tryon_jobs.plan is
  'Deterministic execution plan built at submit: ordered steps with the canonical '
  'role and provider routing for each selected garment, plus skipped items and '
  'reasons. The worker executes this, it does not re-derive it.';
comment on column public.tryon_jobs.applied_item_keys is
  'Items whose provider step actually succeeded. A job may only be marked done '
  'when this covers every planned item — a partial look is a failure, not a result.';
comment on column public.tryon_jobs.step_state is
  'Per-step provider prediction ids, statuses, attempt counts and durations.';

-- Finding the jobs that took the legacy provider-auto path, and the ones whose
-- accounting did not balance. Partial so it stays tiny.
create index if not exists tryon_jobs_incomplete_idx
  on public.tryon_jobs (created_at desc)
  where status = 'done'
    and planned_item_keys is not null
    and applied_item_keys is distinct from planned_item_keys;

-- ── canonical category on the two things a look can be built from ────────────
alter table public.wardrobe_items
  add column if not exists canonical_category text,
  -- valid | needs_review. `needs_review` means we could not establish the role
  -- from trustworthy metadata. The item stays fully visible in the closet; it is
  -- only try-on that refuses to guess (§29).
  add column if not exists classification_status text;

alter table public.products
  add column if not exists canonical_category text,
  add column if not exists classification_status text;

comment on column public.wardrobe_items.canonical_category is
  'Wear The Mood canonical garment role (taxonomy.py). Provider-independent. '
  'NULL means unresolved -> not try-on eligible, never a guessed default.';
comment on column public.products.canonical_category is
  'Wear The Mood canonical garment role (taxonomy.py). Provider-independent.';

create index if not exists wardrobe_items_canonical_idx
  on public.wardrobe_items (user_id, canonical_category);
create index if not exists products_canonical_idx
  on public.products (canonical_category)
  where canonical_category is not null;

-- Rows the backfill still has to answer for. Partial, so it is cheap to count
-- and shrinks to nothing as the data is cleaned up.
create index if not exists wardrobe_items_needs_category_idx
  on public.wardrobe_items (user_id)
  where canonical_category is null;
create index if not exists products_needs_category_idx
  on public.products (merchant_id)
  where canonical_category is null;

-- The audit snapshot has to see the new fields, or the before/after on the RPC
-- below would record a change to something it does not show. Identical to the
-- 0068 definition with two columns added.
create or replace function public.admin_product_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select p.id, p.title, p.active, p.try_on_status, p.image_rights_status,
           p.image_rights_override,
           public.product_effective_image_rights(p) as effective_image_rights,
           p.rights_basis, p.rights_reference, p.rights_verified_at, p.rights_verified_by,
           p.tryon_policy_override,
           public.merchant_tryon_mode(p.merchant_id) as merchant_tryon_mode,
           public.product_effective_tryon_policy(p) as effective_tryon_policy,
           public.product_tryon_ready(p) as tryon_ready,
           p.stock_status, p.manual_override, p.manual_override_fields,
           p.tryon_image_url, p.tryon_image_source,
           p.category, p.subcategory,
           p.canonical_category, p.classification_status
      from public.products p where p.id = p_id
  ) s;
$$;

-- ── operator fix-up for a product the feed could not describe ───────────────
-- Ships in phase A, BEFORE the gate in 0070, so the tool to correct a product
-- exists before anything can be blocked by it. `products.category` stays the
-- merchant's free text — it is their field and other surfaces read it — and only
-- the canonical role is set here, which is ours.
--
-- Setting a role also CLEARS `needs_review`: an operator naming the garment is
-- the review. Passing NULL puts a row back into needs_review, which is how a
-- wrong classification is retracted without inventing a replacement.
create or replace function public.admin_set_product_canonical_category(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_canonical text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_old text;
begin
  perform admin_assert_active(p_admin_id);

  if p_canonical is not null and p_canonical not in (
    'top','bottom','one_piece','outerwear','hijab_scarf','glasses',
    'hat_headwear','shoes','bag','jewelry','belt','other'
  ) then
    raise exception 'VALIDATION_ERROR: canonical category %', p_canonical
      using errcode = '22023';
  end if;

  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  select canonical_category into v_old from public.products where id = p_product_id;

  update public.products
     set canonical_category = p_canonical,
         classification_status = case
           when p_canonical is null then 'needs_review' else 'valid' end,
         updated_at = now()
   where id = p_product_id;

  v_after := admin_product_snapshot(p_product_id);

  return admin_log_audit(
    p_admin_id, p_admin_email,
    case when p_canonical is null then 'product_clear_canonical_category'
         else 'product_set_canonical_category' end,
    'product', p_product_id::text, p_reason,
    jsonb_build_object('previous_category', v_old, 'new_category', p_canonical),
    v_before, v_after
  );
end;
$$;

revoke all on function
  public.admin_set_product_canonical_category(uuid,text,uuid,text,text) from public;
grant execute on function
  public.admin_set_product_canonical_category(uuid,text,uuid,text,text) to service_role;
