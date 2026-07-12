# Admin sync checklist — "you added a feature, now add it to admin"

The 2026-07-13 audit (`ADMIN_GAP_REPORT.md`) found that every app feature shipped
after the console was built had become invisible and un-moderatable. This
checklist + the drift check keep that from happening again.

## One-command drift check (run before every release, and after any migration)

```
cd backend
.venv/Scripts/python.exe scripts/admin_drift_check.py
```

Static, no DB. Fails (exit 1) when:
- the console calls an RPC no migration defines (rename/removal drift);
- the app or backend files a `reports.subject_type` the report queue can't
  resolve or the reports page can't render;
- a new table has neither admin coverage nor an allowlist entry in the script.

If it flags a new table you *deliberately* won't cover (private/biometric data,
plumbing), add it to `TABLE_ALLOWLIST` in `backend/scripts/admin_drift_check.py`
**with a reason** — that's the documented decision.

## When you add a new user-generated / user-visible entity

1. **Migration** — include the standard moderation columns from day one:
   `status` (or `hidden_at`), `deleted_at`, `moderated_by uuid`,
   `moderation_reason text`, `is_seed boolean` (if seedable). Soft delete only.
2. **Admin RPCs** — `admin_list_<entity>` (search/filter/paginate, jsonb) +
   audited mutations (`admin_assert_active` → mutate → `moderation_actions` →
   `admin_log_audit`, all in one function body). Grants: revoke from
   public/anon/authenticated, grant to service_role (copy the loop at the end
   of any admin migration).
3. **Console** — list page + row actions following `/posts` (or `/giveaways`);
   every mutation: `requirePermission` → Zod → RPC → `revalidatePath`.
4. **Report queue** — if the entity is reportable, add its `subject_type` case
   to `admin_list_reports` (new migration, CREATE OR REPLACE) **and** a preview
   branch + action in `reports/page.tsx`.
5. **Backend serve paths** — public reads must exclude hidden/deleted rows.
6. **Types** — if the console reads the table directly with `.from()`, add it to
   `TABLES` in `backend/scripts/gen_admin_db_types.py`, regenerate, and use
   `Pick<>` from `db.generated.ts` in the DAL.
7. **Re-run the drift check** — it should pass without touching the allowlist.

## When a migration renames/drops a column the console touches

Regenerate the shared types and let `tsc` find the breakage:

```
cd backend && .venv/Scripts/python.exe scripts/gen_admin_db_types.py
cd ../admin-web && npm run typecheck
```

## Deploy reminder

Admin console + backend deploy is MANUAL (file-sync → droplet →
`docker compose up -d --build`); migrations apply dev-first via
`backend/scripts/apply_sql.py`, then prod. See `OPS_RUNBOOK.md`.
