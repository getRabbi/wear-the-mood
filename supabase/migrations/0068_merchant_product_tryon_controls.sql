-- 0068 — permission and enablement are two different switches.
--
-- 0067 gave the console a way to ANSWER "may we feed this image to a generative
-- render". What it left implicit is the second question, which 0067 answered by
-- accident: once a merchant was licensed, every product it had that carried a
-- usable image became try-on eligible, all at once, with no way to say "these
-- three only" and no way to switch it off again without un-licensing — that is,
-- without retracting a factual statement about permission in order to perform an
-- operational rollback.
--
-- Those are not the same thing and they must not share a control:
--
--   RIGHTS      a claim about the world. Do we have permission?
--   COVERAGE    a decision about our product. Do we want it on, and for what?
--
-- A product may legitimately be `licensed` and switched OFF (we have permission
-- and choose not to use it yet). The reverse must never resolve: switched ON
-- with rights `unknown` is NOT ELIGIBLE, and this migration is careful that no
-- operational toggle anywhere can outrank the rights gate.
--
-- ── the model ───────────────────────────────────────────────────────────────
--
--   merchant_tryon_policy.mode  (new)   off | all | selected
--   products.tryon_policy_override      on | off | NULL = inherit the mode
--
--   effective policy =
--     mode 'off'       -> OFF always. A hard kill: a product override of 'on'
--                         cannot bypass it, and nothing is erased, so restoring
--                         the mode restores every product decision underneath.
--     mode 'all'       -> ON unless this product says 'off'.
--     mode 'selected'  -> OFF unless this product says 'on'.
--
-- Inheritance is resolved at READ time, deliberately. The alternative — stamping
-- `on` across a merchant's products — would take a switch that should be one row
-- and make it a hundred thousand writes, would not reach products imported
-- tomorrow, and would turn "switch it back on" into a second migration-sized
-- event. Rights propagate (0067) because a rights value is a per-product fact
-- that survives its merchant; coverage does not, because it is a live policy.
--
-- ── why a table rather than a column on merchant_feed_config ────────────────
-- `image_rights_default` lives on the feed config, and 0067 therefore refuses to
-- set rights for a merchant that has no feed — reasonably, since there is no
-- import to apply a default to. Coverage has no such excuse: a merchant whose
-- products were added by hand still needs an off switch, and SELECTED-only mode
-- over a hand-curated merchant is precisely the "we have permission for these
-- three items" case. A separate table lets every merchant have a mode, and lets
-- absence mean `off`.
--
-- ── what this migration does NOT do ─────────────────────────────────────────
-- It inserts no rows. Not one merchant gets a policy row, so every merchant in
-- every environment reads `off` the moment this lands, and the catalog's try-on
-- exposure after this migration is a SUBSET of what it was before. No rights
-- value is read, written or implied anywhere below. Turning anything on is an
-- operator's act, from the console, with their name on the audit row.
--
-- Additive and idempotent.

-- ── merchant coverage ───────────────────────────────────────────────────────
create table if not exists public.merchant_tryon_policy (
  merchant_id uuid primary key references public.merchants (id) on delete cascade,

  -- The operational switch. Never a rights value: see the header.
  mode text not null default 'off'
    check (mode in ('off', 'all', 'selected')),

  updated_at timestamptz not null default now(),
  -- The email, not a foreign key: this is a display field for an operator
  -- reading the merchant card, and the authoritative trail is admin_audit_log.
  updated_by text
);

comment on table public.merchant_tryon_policy is
  'Per-merchant AI try-on COVERAGE (off | all | selected). Operational, not a '
  'rights claim — see merchant_feed_config.image_rights_default for that. A '
  'merchant with no row here is off.';

comment on column public.merchant_tryon_policy.mode is
  'off = hard kill for every product regardless of its own override. '
  'all = on for products that pass every other gate, unless the product says off. '
  'selected = off unless the product says on.';

-- Default-deny, exactly like merchant_feed_config. The resolver below is the
-- only read path, and it is SECURITY DEFINER for that reason.
alter table public.merchant_tryon_policy enable row level security;

-- ── the product-level operational override ──────────────────────────────────
alter table public.products
  add column if not exists tryon_policy_override text
    check (tryon_policy_override in ('on', 'off'));

comment on column public.products.tryon_policy_override is
  'Explicit per-product try-on ENABLEMENT decision. NULL inherits the merchant '
  'mode. Never a rights decision (see image_rights_override) and never able to '
  'outrank one. The importer does not write this column at all.';

-- Overrides are the exception, not the rule, so the useful index is the partial
-- one: counting them per merchant and listing them is what the console does.
create index if not exists products_tryon_override_idx
  on public.products (merchant_id, tryon_policy_override)
  where tryon_policy_override is not null;

-- ── rights evidence ─────────────────────────────────────────────────────────
-- Not a gate. `licensed` already means "someone verified this"; what was missing
-- is the ability to say WHAT they verified, six months later, to somebody who
-- was not there. Free text plus a closed vocabulary for the kind of basis, so
-- the common cases are searchable and the unusual one is still recordable.
do $$
begin
  execute 'alter table public.merchant_feed_config '
          'add column if not exists rights_basis text, '
          'add column if not exists rights_reference text, '
          'add column if not exists rights_verified_at timestamptz, '
          'add column if not exists rights_verified_by text';
  execute 'alter table public.products '
          'add column if not exists rights_basis text, '
          'add column if not exists rights_reference text, '
          'add column if not exists rights_verified_at timestamptz, '
          'add column if not exists rights_verified_by text';
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'merchant_feed_config_rights_basis_check'
  ) then
    alter table public.merchant_feed_config
      add constraint merchant_feed_config_rights_basis_check
      check (rights_basis is null or rights_basis in
        ('merchant_permission', 'product_permission', 'programme_terms',
         'network_permission', 'other'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'products_rights_basis_check'
  ) then
    alter table public.products
      add constraint products_rights_basis_check
      check (rights_basis is null or rights_basis in
        ('merchant_permission', 'product_permission', 'programme_terms',
         'network_permission', 'other'));
  end if;
end $$;

comment on column public.products.rights_reference is
  'What the rights decision rests on: an agreement reference, the date of a '
  'permission email, a ticket, or an internal note. Evidence for a human, never '
  'read by a gate.';

-- ── the coverage resolver ───────────────────────────────────────────────────
-- SECURITY DEFINER because merchant_tryon_policy is default-deny and this has to
-- answer for `authenticated` and `anon` — product_tryon_ready() is granted to
-- both so the app can filter, and a resolver that returned `off` to clients and
-- `all` to the service role would be the exact drift this file exists to avoid.
--
-- It returns one of three literal strings and reads nothing else, so nothing
-- privileged escapes through it.
create or replace function public.merchant_tryon_mode(p_merchant_id uuid)
returns text language sql stable security definer set search_path = public as $$
  -- No row is a real answer, and it is `off`: a merchant nobody has made a
  -- decision about has not been decided in favour.
  select coalesce(
    (select t.mode from public.merchant_tryon_policy t where t.merchant_id = p_merchant_id),
    'off'
  )
$$;

comment on function public.merchant_tryon_mode(uuid) is
  'The merchant AI try-on coverage mode, or off when no policy row exists.';

grant execute on function public.merchant_tryon_mode(uuid)
  to anon, authenticated, service_role;

-- ── effective coverage for one product ──────────────────────────────────────
create or replace function public.product_effective_tryon_policy(p public.products)
returns text language sql stable as $$
  select case public.merchant_tryon_mode(p.merchant_id)
    -- The kill switch. Checked FIRST and unconditionally, so a product marked
    -- `on` under a merchant that has since been shut off is off — which is what
    -- makes this a rollback rather than a suggestion.
    when 'off' then 'off'
    when 'all' then case when p.tryon_policy_override = 'off' then 'off' else 'on' end
    when 'selected' then case when p.tryon_policy_override = 'on' then 'on' else 'off' end
    else 'off'
  end
$$;

comment on function public.product_effective_tryon_policy(public.products) is
  'on | off — the merchant mode with this product override applied. Says nothing '
  'about rights: product_tryon_ready() requires both.';

grant execute on function public.product_effective_tryon_policy(public.products)
  to anon, authenticated, service_role;

-- ── the gate, with coverage added and nothing removed ───────────────────────
-- Every condition 0065/0067 imposed is still here and still required. The only
-- change is one more AND, which can make a product ineligible and can never make
-- one eligible.
create or replace function public.product_tryon_ready(p public.products)
returns boolean language sql stable as $$
  select p.try_on_status = 'ready'
     -- RIGHTS. Authoritative, and first: no operational toggle outranks it.
     and public.product_effective_image_rights(p) = 'licensed'
     -- COVERAGE. The operator's decision about whether we use that permission.
     and public.product_effective_tryon_policy(p) = 'on'
     and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
$$;

comment on function public.product_tryon_ready(public.products) is
  'May this product be used as AI try-on INPUT. Requires licensed effective '
  'rights, an ON effective coverage policy, an earned ready status and a usable '
  'image. The single definition every surface reads.';

-- ── readiness, explained ────────────────────────────────────────────────────
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
      when p.try_on_status = 'pending' then 'status_pending'
      else 'status_not_ready'
    end
  )
$$;

grant execute on function public.product_tryon_readiness(public.products)
  to service_role;

-- ── product snapshot: the audit has to see the new fields ───────────────────
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
           p.tryon_image_url, p.tryon_image_source
      from public.products p where p.id = p_id
  ) s;
$$;

create or replace function public.admin_merchant_snapshot(p_id uuid)
returns jsonb language sql stable set search_path = public as $$
  select to_jsonb(s) from (
    select m.id, m.name, m.approved, m.feed_health,
           c.enabled as feed_enabled, c.image_rights_default,
           c.rights_basis, c.rights_reference, c.rights_verified_at, c.rights_verified_by,
           public.merchant_tryon_mode(m.id) as tryon_mode
      from public.merchants m
      left join public.merchant_feed_config c on c.merchant_id = m.id
     where m.id = p_id
  ) s;
$$;

-- ── merchant diagnostics ────────────────────────────────────────────────────
-- The numbers the console renders on a merchant card and inside the mode-change
-- confirmation. Computed HERE, from the canonical functions, because a count a
-- browser derived is a count that can disagree with what users get.
create or replace function public.admin_merchant_tryon_summary(p_merchant_id uuid)
returns table (
  merchant_id uuid, merchant_name text,
  image_rights_default text, tryon_mode text, has_feed_config boolean,
  total_products bigint,
  tryon_ready bigint,
  rights_licensed bigint,
  blocked_rights bigint,
  blocked_no_image bigint,
  blocked_status bigint,
  explicitly_enabled bigint,
  explicitly_disabled bigint,
  awaiting_selection bigint,
  eligible_if_all bigint,
  eligible_if_selected bigint
)
language sql stable security definer set search_path = public
as $$
  with p as (
    select pr.*,
           public.product_effective_image_rights(pr) as eff_rights,
           coalesce(nullif(pr.tryon_image_url, ''), (pr.image_urls)[1]) as img,
           public.product_tryon_ready(pr) as ready
      from public.products pr
     where pr.merchant_id = p_merchant_id
  )
  select m.id, m.name,
         coalesce(c.image_rights_default, 'unknown'),
         public.merchant_tryon_mode(m.id),
         c.merchant_id is not null,
         (select count(*) from p),
         (select count(*) from p where p.ready),
         (select count(*) from p where p.eff_rights = 'licensed'),
         (select count(*) from p where p.eff_rights <> 'licensed'),
         -- Counted among rights-licensed rows only, so "92 missing compatible
         -- images" is a queue of work rather than a restatement of the rights
         -- number in different words.
         (select count(*) from p where p.eff_rights = 'licensed' and p.img is null),
         (select count(*) from p
           where p.eff_rights = 'licensed' and p.img is not null
             and p.try_on_status <> 'ready'),
         (select count(*) from p where p.tryon_policy_override = 'on'),
         (select count(*) from p where p.tryon_policy_override = 'off'),
         -- Under SELECTED, the rows that pass everything technical and are
         -- simply waiting to be picked. `is null`, not `is distinct from 'on'`:
         -- a product somebody deliberately switched off is a decision that has
         -- been made, and listing it as work outstanding would invite an
         -- operator to undo it.
         (select count(*) from p
           where public.merchant_tryon_mode(p_merchant_id) = 'selected'
             and p.tryon_policy_override is null
             and p.eff_rights = 'licensed' and p.img is not null
             and p.try_on_status = 'ready'),
         -- What switching the mode would actually expose. The honest number for
         -- the confirmation dialog: everything technical already passes, so the
         -- mode is the only thing left.
         (select count(*) from p
           where p.eff_rights = 'licensed' and p.img is not null
             and p.try_on_status = 'ready'
             and p.tryon_policy_override is distinct from 'off'),
         (select count(*) from p
           where p.eff_rights = 'licensed' and p.img is not null
             and p.try_on_status = 'ready'
             and p.tryon_policy_override = 'on')
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
   where m.id = p_merchant_id;
$$;

comment on function public.admin_merchant_tryon_summary(uuid) is
  'Canonical per-merchant try-on diagnostics for the console. Every count comes '
  'from the same functions the app and RLS read.';

-- ── merchant coverage: the mode switch ──────────────────────────────────────
create or replace function public.admin_set_merchant_tryon_mode(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid,
  p_mode text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_before jsonb; v_after jsonb; v_old text; v_name text;
  v_exposed bigint; v_overrides bigint;
begin
  perform admin_assert_active(p_admin_id);

  if p_mode is null or p_mode not in ('off', 'all', 'selected') then
    raise exception 'VALIDATION_ERROR: try-on mode %', p_mode using errcode = '22023';
  end if;

  select m.name into v_name from public.merchants m where m.id = p_merchant_id;
  if v_name is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;

  -- Deliberately NOT gated on a feed config. A merchant whose products were
  -- added by hand has no feed and still needs an off switch.
  v_old := public.merchant_tryon_mode(p_merchant_id);
  v_before := admin_merchant_snapshot(p_merchant_id);

  insert into public.merchant_tryon_policy (merchant_id, mode, updated_by)
  values (p_merchant_id, p_mode, p_admin_email)
  on conflict (merchant_id)
    do update set mode = excluded.mode,
                  updated_by = excluded.updated_by,
                  updated_at = now();

  -- Product overrides are NEVER touched here. That is what makes `off` a
  -- rollback: restoring the mode restores every decision underneath it.
  select count(*) filter (where public.product_tryon_ready(p)),
         count(*) filter (where p.tryon_policy_override is not null)
    into v_exposed, v_overrides
    from public.products p where p.merchant_id = p_merchant_id;

  v_after := admin_merchant_snapshot(p_merchant_id);

  return admin_log_audit(
    p_admin_id, p_admin_email, 'merchant_set_tryon_mode',
    'merchant', p_merchant_id::text, p_reason,
    jsonb_build_object(
      'previous_mode', v_old, 'new_mode', p_mode,
      'products_try_on_ready_after', v_exposed,
      'product_overrides_preserved', v_overrides
    ),
    v_before, v_after
  );
end;
$$;

comment on function public.admin_set_merchant_tryon_mode(uuid,text,uuid,text,text) is
  'Set merchant AI try-on coverage. Grants no rights and erases no product '
  'override; off is a reversible kill switch.';

-- ── product coverage: on / off / inherit ────────────────────────────────────
create or replace function public.admin_set_product_tryon_override(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_override text, p_reason text
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_old text;
begin
  perform admin_assert_active(p_admin_id);

  -- NULL is a real value and means inherit.
  if p_override is not null and p_override not in ('on', 'off') then
    raise exception 'VALIDATION_ERROR: try-on override %', p_override using errcode = '22023';
  end if;

  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  select tryon_policy_override into v_old from public.products where id = p_product_id;

  update public.products
     set tryon_policy_override = p_override, updated_at = now()
   where id = p_product_id;

  -- try_on_status is NOT recomputed. It is the technical readiness marker
  -- (rights + a usable image); coverage is a policy laid over it, and collapsing
  -- the two would mean switching a product off destroyed the record of whether
  -- it was ever renderable.
  v_after := admin_product_snapshot(p_product_id);

  return admin_log_audit(
    p_admin_id, p_admin_email,
    case when p_override is null then 'product_clear_tryon_override'
         else 'product_set_tryon_override' end,
    'product', p_product_id::text, p_reason,
    jsonb_build_object('previous_override', v_old, 'new_override', p_override),
    v_before, v_after
  );
end;
$$;

-- ── bulk coverage ───────────────────────────────────────────────────────────
-- SELECTED-only administration is unusable if picking twenty products means
-- opening twenty pages. This is that action — and it is careful about the one
-- thing a bulk control must never do quietly: it writes coverage and ONLY
-- coverage. Products in the selection whose rights are not licensed are switched
-- on and reported as still ineligible, never licensed to make the number look
-- better.
create or replace function public.admin_bulk_set_product_tryon(
  p_admin_id uuid, p_admin_email text, p_product_ids uuid[],
  p_override text, p_reason text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_requested int; v_updated int; v_ready int; v_unlicensed int;
  v_blocked jsonb; v_merchants jsonb;
begin
  perform admin_assert_active(p_admin_id);

  if p_override is not null and p_override not in ('on', 'off') then
    raise exception 'VALIDATION_ERROR: try-on override %', p_override using errcode = '22023';
  end if;
  v_requested := coalesce(array_length(p_product_ids, 1), 0);
  if v_requested = 0 then
    raise exception 'VALIDATION_ERROR: no products selected' using errcode = '22023';
  end if;
  -- A bound, because an unbounded id array is an unbounded statement and this
  -- runs inside one transaction with the audit row.
  if v_requested > 500 then
    raise exception 'VALIDATION_ERROR: select at most 500 products at a time'
      using errcode = '22023';
  end if;

  update public.products
     set tryon_policy_override = p_override, updated_at = now()
   where id = any(p_product_ids);
  get diagnostics v_updated = row_count;

  select count(*) filter (where public.product_tryon_ready(p)),
         count(*) filter (where public.product_effective_image_rights(p) <> 'licensed'),
         -- The specific rows an operator has to go and deal with, capped so a
         -- 500-row selection cannot write a megabyte of audit metadata.
         coalesce(jsonb_agg(jsonb_build_object(
             'id', p.id, 'title', p.title,
             'rights', public.product_effective_image_rights(p)
           )) filter (where public.product_effective_image_rights(p) <> 'licensed'),
           '[]'::jsonb),
         coalesce(jsonb_agg(distinct p.merchant_id), '[]'::jsonb)
    into v_ready, v_unlicensed, v_blocked, v_merchants
    from public.products p
   where p.id = any(p_product_ids);

  perform admin_log_audit(
    p_admin_id, p_admin_email,
    case when p_override is null then 'product_bulk_clear_tryon_override'
         else 'product_bulk_set_tryon_override' end,
    'product', 'bulk', p_reason,
    jsonb_build_object(
      'new_override', p_override,
      'requested', v_requested,
      'updated', v_updated,
      'try_on_ready_after', v_ready,
      'not_licensed', v_unlicensed,
      'merchants', v_merchants,
      'blocked_sample', (select jsonb_agg(e) from (
         select e from jsonb_array_elements(v_blocked) e limit 25
      ) s)
    ),
    null, null
  );

  return jsonb_build_object(
    'requested', v_requested,
    'updated', v_updated,
    'try_on_ready_after', v_ready,
    'not_licensed', v_unlicensed,
    'blocked', v_blocked
  );
end;
$$;

comment on function public.admin_bulk_set_product_tryon(uuid,text,uuid[],text,text) is
  'Set try-on coverage across a selection. Writes coverage only — a selected '
  'product whose rights are not licensed stays ineligible and is reported.';

-- ── rights, now with evidence ───────────────────────────────────────────────
-- Both functions keep every rule 0067 gave them. The additions are two optional
-- parameters recording WHAT was verified, and the timestamp/actor written from
-- the call itself so they cannot disagree with the audit row.
--
-- Defaults on the new parameters so a five-argument call from a console that has
-- not been redeployed yet still resolves. Dropping first because the parameter
-- list changes.
drop function if exists public.admin_set_merchant_image_rights(uuid,text,uuid,text,text);

create or replace function public.admin_set_merchant_image_rights(
  p_admin_id uuid, p_admin_email text, p_merchant_id uuid,
  p_rights text, p_reason text,
  p_basis text default null, p_reference text default null
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare
  v_before jsonb; v_after jsonb; v_old text; v_name text; v_affected int;
begin
  perform admin_assert_active(p_admin_id);

  if p_rights is null or p_rights not in ('unknown', 'licensed', 'restricted') then
    raise exception 'VALIDATION_ERROR: image rights %', p_rights using errcode = '22023';
  end if;
  if p_basis is not null and p_basis not in
     ('merchant_permission', 'product_permission', 'programme_terms',
      'network_permission', 'other') then
    raise exception 'VALIDATION_ERROR: rights basis %', p_basis using errcode = '22023';
  end if;

  select m.name, c.image_rights_default
    into v_name, v_old
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
   where m.id = p_merchant_id;

  if v_name is null then
    raise exception 'MERCHANT_NOT_FOUND: %', p_merchant_id using errcode = 'P0002';
  end if;
  if v_old is null then
    raise exception 'NO_FEED_CONFIG: %', p_merchant_id using errcode = 'P0002';
  end if;

  v_before := admin_merchant_snapshot(p_merchant_id);

  update public.merchant_feed_config
     set image_rights_default = p_rights,
         -- Evidence belongs to the CLAIM. Licensing records who verified what;
         -- withdrawing to unknown/restricted clears it, because the old
         -- reference no longer describes the state of the row.
         rights_basis       = case when p_rights = 'licensed' then p_basis else null end,
         rights_reference   = case when p_rights = 'licensed' then nullif(btrim(coalesce(p_reference, '')), '') else null end,
         rights_verified_at = case when p_rights = 'licensed' then now() else null end,
         rights_verified_by = case when p_rights = 'licensed' then p_admin_email else null end,
         updated_at = now()
   where merchant_id = p_merchant_id;

  -- PROPAGATION. Inheriting rows only — an explicit product decision is a
  -- decision, and a merchant-wide change is not permission to discard it.
  update public.products
     set image_rights_status = p_rights, updated_at = now()
   where merchant_id = p_merchant_id
     and image_rights_override is null
     and image_rights_status is distinct from p_rights;
  get diagnostics v_affected = row_count;

  update public.products p
     set try_on_status = case
           when p.try_on_status = 'pending' then 'pending'
           when public.product_effective_image_rights(p) = 'licensed'
                and coalesce(nullif(p.tryon_image_url, ''), (p.image_urls)[1]) is not null
             then 'ready'
           else 'unsupported'
         end,
         updated_at = now()
   where p.merchant_id = p_merchant_id
     and p.image_rights_override is null;

  v_after := admin_merchant_snapshot(p_merchant_id);

  return admin_log_audit(
    p_admin_id, p_admin_email, 'merchant_set_image_rights',
    'merchant', p_merchant_id::text, p_reason,
    jsonb_build_object(
      'scope', 'merchant_default',
      'products_repointed', v_affected,
      'rights_basis', p_basis,
      -- Licensing a merchant does NOT switch coverage on. Recorded so the audit
      -- shows the two decisions staying separate rather than leaving a reader to
      -- wonder whether one implied the other.
      'tryon_mode_unchanged', public.merchant_tryon_mode(p_merchant_id)
    ),
    v_before, v_after
  );
end;
$$;

drop function if exists public.admin_set_product_image_rights(uuid,text,uuid,text,text);

create or replace function public.admin_set_product_image_rights(
  p_admin_id uuid, p_admin_email text, p_product_id uuid,
  p_rights text, p_reason text,
  p_basis text default null, p_reference text default null
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_before jsonb; v_after jsonb; v_old text; v_status text;
begin
  perform admin_assert_active(p_admin_id);

  if p_rights is not null and p_rights not in ('unknown', 'licensed', 'restricted') then
    raise exception 'VALIDATION_ERROR: image rights %', p_rights using errcode = '22023';
  end if;
  if p_basis is not null and p_basis not in
     ('merchant_permission', 'product_permission', 'programme_terms',
      'network_permission', 'other') then
    raise exception 'VALIDATION_ERROR: rights basis %', p_basis using errcode = '22023';
  end if;

  v_before := admin_product_snapshot(p_product_id);
  if v_before is null then
    raise exception 'PRODUCT_NOT_FOUND: %', p_product_id using errcode = 'P0002';
  end if;
  select image_rights_override into v_old from public.products where id = p_product_id;

  update public.products
     set image_rights_override = p_rights,
         rights_basis       = case when p_rights = 'licensed' then p_basis else null end,
         rights_reference   = case when p_rights = 'licensed' then nullif(btrim(coalesce(p_reference, '')), '') else null end,
         rights_verified_at = case when p_rights = 'licensed' then now() else null end,
         rights_verified_by = case when p_rights = 'licensed' then p_admin_email else null end,
         updated_at = now()
   where id = p_product_id;

  v_status := public.product_recompute_tryon_status(p_product_id);

  v_after := admin_product_snapshot(p_product_id);

  return admin_log_audit(
    p_admin_id, p_admin_email,
    case when p_rights is null then 'product_clear_image_rights_override'
         else 'product_set_image_rights_override' end,
    'product', p_product_id::text, p_reason,
    jsonb_build_object(
      'scope', 'product_override',
      'previous_override', v_old,
      'new_override', p_rights,
      'rights_basis', p_basis,
      'try_on_status', v_status
    ),
    v_before, v_after
  );
end;
$$;

-- ── the merchant list, with coverage ────────────────────────────────────────
drop function if exists public.admin_list_merchants();

create or replace function public.admin_list_merchants()
returns table (
  id uuid, slug text, name text, approved boolean, feed_health text,
  allowed_domains text[], supported_countries text[], shipping_countries text[],
  last_synced_at timestamptz, product_count bigint, active_product_count bigint,
  feed_url_host text, feed_enabled boolean, feed_format text,
  consecutive_failures integer, retry_after timestamptz, locked_at timestamptz,
  image_rights_default text, affiliate_status text, affiliate_configured boolean,
  tryon_mode text, rights_basis text, rights_reference text,
  rights_verified_at timestamptz, rights_verified_by text
)
language sql stable security definer set search_path = public
as $$
  select m.id, m.slug, m.name, m.approved, m.feed_health,
         m.allowed_domains, m.supported_countries, m.shipping_countries,
         m.last_synced_at,
         (select count(*) from public.products p where p.merchant_id = m.id),
         (select count(*) from public.products p where p.merchant_id = m.id and p.active),
         -- The HOST only. A feed URL can carry an API key in its query string,
         -- and this value is rendered in a browser.
         case when c.feed_url is null then null
              else split_part(split_part(replace(replace(c.feed_url, 'https://', ''),
                                                 'http://', ''), '/', 1), '@', -1)
         end,
         coalesce(c.enabled, false), c.feed_format,
         coalesce(c.consecutive_failures, 0), c.retry_after, c.locked_at,
         c.image_rights_default,
         -- The STATUS, never the tag: the affiliate tag identifies the account
         -- that gets paid and must not reach a browser (§40).
         a.status, (a.merchant_id is not null),
         public.merchant_tryon_mode(m.id),
         c.rights_basis, c.rights_reference, c.rights_verified_at, c.rights_verified_by
    from public.merchants m
    left join public.merchant_feed_config c on c.merchant_id = m.id
    left join public.merchant_affiliate_config a on a.merchant_id = m.id
   order by m.name;
$$;

-- ── the product list, with coverage ─────────────────────────────────────────
drop function if exists public.admin_list_products(text, uuid, text, text, integer, integer);

create or replace function public.admin_list_products(
  p_search text default null,
  p_merchant_id uuid default null,
  p_status text default null,      -- active | inactive | all
  p_try_on text default null,      -- ready | pending | unsupported
  p_limit integer default 50,
  p_offset integer default 0
) returns table (
  id uuid, external_id text, title text, brand text, category text,
  subcategory text, audience text,
  price_minor bigint, currency char(3), stock_status text, try_on_status text,
  image_rights_status text, active boolean, sponsored boolean,
  merchant_id uuid, merchant_name text, merchant_approved boolean,
  servable boolean, tryon_ready boolean,
  manual_override boolean, manual_override_fields text[],
  tryon_image_url text, tryon_image_source text,
  image_urls text[], last_synced_at timestamptz, last_seen_in_feed_at timestamptz,
  missing_run_count integer, deactivated_by_sync_at timestamptz,
  country_eligibility text, affiliate_host text,
  image_rights_override text, effective_image_rights text,
  merchant_image_rights_default text, tryon_readiness jsonb,
  tryon_policy_override text, merchant_tryon_mode text, effective_tryon_policy text,
  rights_basis text, rights_reference text,
  rights_verified_at timestamptz, rights_verified_by text,
  total_count bigint
)
language sql stable security definer set search_path = public
as $$
  with filtered as (
    select p.*, public.product_is_servable(p) as is_servable,
           public.product_tryon_ready(p) as is_tryon_ready,
           public.product_effective_image_rights(p) as effective_rights,
           public.product_effective_tryon_policy(p) as effective_policy,
           public.merchant_tryon_mode(p.merchant_id) as m_tryon_mode,
           public.product_tryon_readiness(p) as readiness,
           m.name as m_name, m.approved as m_approved,
           coalesce(c.image_rights_default, 'unknown') as m_rights_default
      from public.products p
      join public.merchants m on m.id = p.merchant_id
      left join public.merchant_feed_config c on c.merchant_id = m.id
     where (p_merchant_id is null or p.merchant_id = p_merchant_id)
       and (p_try_on is null or p.try_on_status = p_try_on)
       and (p_status is null or p_status = 'all'
            or (p_status = 'active' and p.active)
            or (p_status = 'inactive' and not p.active))
       and (
         p_search is null or p_search = '' or
         p.title ilike '%' || p_search || '%' or
         p.external_id ilike '%' || p_search || '%' or
         coalesce(p.brand, '') ilike '%' || p_search || '%'
       )
  )
  select f.id, f.external_id, f.title, f.brand, f.category,
         f.subcategory, f.audience,
         f.price_minor, f.currency, f.stock_status, f.try_on_status,
         f.image_rights_status, f.active, f.sponsored,
         f.merchant_id, f.m_name, f.m_approved,
         f.is_servable, f.is_tryon_ready, f.manual_override,
         f.manual_override_fields, f.tryon_image_url, f.tryon_image_source,
         f.image_urls, f.last_synced_at, f.last_seen_in_feed_at,
         f.missing_run_count, f.deactivated_by_sync_at,
         f.country_eligibility,
         case when coalesce(f.affiliate_ref, '') = '' then null
              else split_part(split_part(replace(replace(f.affiliate_ref,
                     'https://', ''), 'http://', ''), '/', 1), '?', 1) end,
         f.image_rights_override, f.effective_rights,
         f.m_rights_default, f.readiness,
         f.tryon_policy_override, f.m_tryon_mode, f.effective_policy,
         f.rights_basis, f.rights_reference, f.rights_verified_at, f.rights_verified_by,
         count(*) over ()
    from filtered f
   order by f.updated_at desc
   limit greatest(1, least(coalesce(p_limit, 50), 200))
  offset greatest(0, coalesce(p_offset, 0));
$$;

-- ── grants ──────────────────────────────────────────────────────────────────
-- Same contract as every other admin mutation: service_role only. The two
-- resolvers above are the exception and were granted deliberately, because the
-- app has to be able to ask the same question the console asks.
do $$
declare fn text;
begin
  foreach fn in array array[
    'admin_set_merchant_tryon_mode(uuid,text,uuid,text,text)',
    'admin_set_product_tryon_override(uuid,text,uuid,text,text)',
    'admin_bulk_set_product_tryon(uuid,text,uuid[],text,text)',
    'admin_merchant_tryon_summary(uuid)',
    'admin_set_merchant_image_rights(uuid,text,uuid,text,text,text,text)',
    'admin_set_product_image_rights(uuid,text,uuid,text,text,text,text)',
    'admin_list_merchants()',
    'admin_list_products(text,uuid,text,text,integer,integer)'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon, authenticated;', fn);
    execute format('grant execute on function public.%s to service_role;', fn);
  end loop;
end $$;
