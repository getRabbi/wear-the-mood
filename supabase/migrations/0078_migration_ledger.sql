-- ============================================================================
-- 0078 — A record of which migrations this database has actually run
--
-- WHY
-- ---
-- On 2026-08-21, build 1.0.23+28 shipped the removal-first Add Garment flow to
-- Google Play against a production database that had never had 0071 applied.
-- Background removal was broken for every user of that build. Nothing caught it,
-- and nothing COULD have, because this repository had no way to answer the
-- question "which migrations has prod run?":
--
--   * `migration-sql` applies whatever filenames a human types into a workflow
--     input, and records nothing afterwards;
--   * `migration-deploy` releases the API dyno and never looks at the schema;
--   * `/readyz` proves the process can reach Postgres, which is a different
--     question from whether Postgres has the columns the process needs.
--
-- So the deploy order (migration → backend → client) was a convention held in
-- somebody's head, and the one time it was not followed there was no signal.
--
-- WHAT IT CHANGES
-- ---------------
-- One new table. It writes nothing, moves nothing and deletes nothing; no
-- existing object changes meaning. Applying it to a database that is already
-- fully migrated is a no-op beyond creating the table.
--
-- WHAT THIS TABLE IS NOT
-- ----------------------
-- It is NOT permission to replay history. Baselining an existing database means
-- inspecting the schema and recording only what is demonstrably already there
-- (`scripts/migrations.py baseline --probe`); a version with no evidence behind
-- it stays UNRECORDED, because a ledger that lies is worse than no ledger — it
-- converts "we do not know" into a confident "yes", which is exactly the failure
-- mode that shipped build 28.
--
-- CHECKSUMS
-- ---------
-- `checksum` is sha256 over the file's bytes with line endings normalised to LF,
-- so a Windows workstation and an Ubuntu runner compute the same value. Editing
-- a migration that has already been applied changes it, and the runner then
-- refuses to continue rather than silently treating the file on disk as though
-- it were the SQL the database ran.
--
-- Idempotent and reversible: `drop table public.schema_migrations`.
-- ============================================================================

create table if not exists public.schema_migrations (
  -- The numeric prefix: '0071'. Unique, so one version can never be recorded
  -- twice, and orderable, so "what is pending" is a simple comparison.
  version      text primary key,
  -- The full filename it came from, kept so a rename is visible rather than
  -- silently producing a second row for the same change.
  filename     text not null,
  checksum     text not null,
  applied_at   timestamptz not null default now(),
  -- How the row got here. 'applied' = this runner executed the SQL.
  -- 'baselined' = the change was found ALREADY PRESENT in the schema by a
  -- capability probe, and recorded on that evidence. The distinction matters
  -- during an incident: a baselined row is an inference from the schema, an
  -- applied row is a receipt.
  source       text not null default 'applied'
                 check (source in ('applied', 'baselined')),
  -- Who/what ran it, for an audit trail. Never a credential.
  applied_by   text
);

comment on table public.schema_migrations is
  'Which ordered SQL migrations this database has run. Written by '
  'backend/app/scripts/migrations.py (and the migration-sql workflow); read by '
  'the release preflight, which refuses to promote a build whose required '
  'migrations are missing. A row is NEVER written for a migration that has not '
  'demonstrably taken effect.';

comment on column public.schema_migrations.checksum is
  'sha256 of the migration file with LF line endings. A mismatch against the '
  'file on disk means the already-applied SQL was edited afterwards, and the '
  'runner stops instead of guessing which version the database actually ran.';

comment on column public.schema_migrations.source is
  '''applied'' — this runner executed the file. ''baselined'' — the change was '
  'observed already present in the schema and recorded on that evidence.';

-- Reading the ledger is how a deploy decides whether it may proceed, so the API
-- role needs it. Writing stays with the migration runner (service_role).
alter table public.schema_migrations enable row level security;

revoke all on table public.schema_migrations from public, anon, authenticated;
grant select on table public.schema_migrations to service_role;
grant insert, update, delete on table public.schema_migrations to service_role;
