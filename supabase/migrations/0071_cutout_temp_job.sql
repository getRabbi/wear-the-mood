-- ============================================================================
-- 0071 — A background removal that does NOT need a wardrobe row yet
--
-- WHY
-- ---
-- Add Garment is meant to run: photo -> background removal -> show the cutout ->
-- ask for a name and a category -> save. The cloud half of that was impossible,
-- because the BiRefNet worker's work queue IS the wardrobe table:
-- `bg_worker.claim_next_item()` selects `from public.wardrobe_items where
-- cutout_status = 'queued'`. The only way to get a cloud cutout was to create the
-- final garment first — before the user had been asked what it is. Once the API
-- began (correctly) requiring a name and a category on every manual create, that
-- sequence could not work at all: the create at the end of a successful removal
-- was refused 422, and the user was shown a background-removal failure for a
-- background removal that had worked.
--
-- The fix is to give the removal somewhere to live that is NOT a garment.
--
-- WHAT IT CHANGES
-- ---------------
-- One additive value on the existing `ai_jobs.job_type` check. `ai_jobs` is
-- already the generic async-job construct (0033): user-scoped, status machine,
-- `input_urls`/`output_urls`, a NULLABLE `source_item_id`, `credits_reserved`
-- defaulting to 0, and a client poller (`GET /v1/ai/jobs/{id}`) that already
-- exists. A temp cutout is exactly that shape, so this reuses it rather than
-- inventing a draft-garment model — which would have meant a row in
-- `wardrobe_items` that every closet, try-on, outfit and analytics query would
-- then have to remember to exclude. Nothing here is a draft GARMENT; it is a
-- draft IMAGE, and it never becomes a garment on its own.
--
-- A `cutout_temp` job:
--   * is never in the closet — it is not a wardrobe row at all;
--   * is never try-on eligible, for the same reason;
--   * spends no credits (`credits_reserved` stays 0) and touches no membership;
--   * cannot bypass the mandatory name/category, because the FINAL create still
--     goes through `POST /v1/wardrobe` and its `_require_metadata` gate;
--   * expires. See the reaper below.
--
-- Idempotent, additive, and reversible: no data is written, moved or deleted,
-- and nothing that exists today changes meaning. Safe to apply before or after
-- 0069/0070 — it touches none of the same objects.
--
-- Rollback: re-run the constraint block below with 'cutout_temp' removed, after
-- deleting any rows carrying it (`delete from public.ai_jobs where job_type =
-- 'cutout_temp'` — they are disposable by construction).
-- ============================================================================

-- ── the job type ────────────────────────────────────────────────────────────
-- Discover the constraint by name rather than assuming Postgres's default, so a
-- re-run (or a database where it was ever renamed) cannot leave the table with
-- two overlapping checks or with none at all.
do $$
declare
  constraint_name text;
begin
  select con.conname into constraint_name
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
   where nsp.nspname = 'public'
     and rel.relname = 'ai_jobs'
     and con.contype = 'c'
     and pg_get_constraintdef(con.oid) ilike '%job_type%';

  if constraint_name is not null then
    execute format('alter table public.ai_jobs drop constraint %I', constraint_name);
  end if;

  alter table public.ai_jobs
    add constraint ai_jobs_job_type_check
    check (job_type in ('enhance_item', 'catalog_model',
                        'tryon_own_photo', 'tryon_studio_model',
                        'cutout_temp'));
end $$;

comment on column public.ai_jobs.job_type is
  'What the job produces. `cutout_temp` is a background removal that has no '
  'garment yet: it carries the uploaded original in input_urls and the finished '
  'cutout in output_urls, so Add Garment can show the result BEFORE asking for '
  'a name and a category. It is not a wardrobe item and never becomes one on '
  'its own — the final create still enforces the mandatory metadata.';

-- ── finding the ones still worth waiting for ────────────────────────────────
-- Partial: the table is dominated by finished jobs, and the worker only ever
-- looks for live ones.
create index if not exists ai_jobs_cutout_temp_live_idx
  on public.ai_jobs (created_at)
  where job_type = 'cutout_temp' and status in ('queued', 'processing');

-- ── expiry ──────────────────────────────────────────────────────────────────
-- A temp cutout is abandoned the moment the user backs out of Add Garment, and
-- nothing else will ever reference it. Without a reaper those rows — and the R2
-- objects they point at — accumulate forever.
--
-- This deliberately deletes only the JOB ROW and returns the object keys it was
-- holding, rather than deleting storage itself: SQL has no business reaching
-- into R2, and the caller (the existing cleanup task) is what knows how. The
-- keys are returned so the caller can delete exactly the objects that just
-- became unreferenced, and NEVER by scanning a prefix — a prefix sweep is how a
-- cleanup job deletes a real garment's cutout.
--
-- `adopted_at` is what makes this safe: the wardrobe create stamps it when it
-- takes ownership of the cutout, and an adopted job's objects are then a
-- garment's objects and must never be swept.
alter table public.ai_jobs
  add column if not exists adopted_at timestamptz;

comment on column public.ai_jobs.adopted_at is
  'When a cutout_temp job''s output was taken over by a real wardrobe item. '
  'Non-null means the objects belong to a garment now and the reaper must '
  'leave them alone. Null on every other job type.';

create or replace function public.reap_expired_cutout_jobs(older_than interval default '24 hours')
returns table (job_id uuid, object_key text)
language sql
security definer
set search_path = public
as $$
  with expired as (
    delete from public.ai_jobs
     where job_type = 'cutout_temp'
       and adopted_at is null
       and created_at < now() - older_than
    returning id, output_urls
  )
  select expired.id, key
    from expired
    cross join lateral unnest(
      case when cardinality(expired.output_urls) > 0
           then expired.output_urls
           else array[]::text[] end
    ) as key
$$;

comment on function public.reap_expired_cutout_jobs(interval) is
  'Delete abandoned temp-cutout jobs and RETURN the storage keys that just '
  'became unreferenced, so the caller can delete exactly those objects. Never '
  'touches an adopted job, and never returns a key belonging to a garment.';

revoke all on function public.reap_expired_cutout_jobs(interval) from public, anon, authenticated;
grant execute on function public.reap_expired_cutout_jobs(interval) to service_role;
