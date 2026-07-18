# PHASE 2 REPORT — Code refactor + reproducible infrastructure

**Objective:** build the new deployable units on the migration branch while DigitalOcean production behavior stays unchanged. No prod deploy, no migration applied to Tokyo, no cloud resources created.

**Starting commit:** `8099855` (Phase 1 end) · **Ending commit:** this commit.

## What was built (11 small commits)

| # | Commit | Deliverable (blueprint) |
|---|---|---|
| 1 | `557c0a0` | Queue abstraction — base/stub/azure + versioned wake messages + routing + best-effort enqueue (§11.2) |
| 2 | `91ff742` | Migration `0044` — attempt/lease/last_signal/error_code + recovery indexes + output uniqueness (§11.3) |
| 3 | `e836209` | Split workers `rembg_worker`/`ai_orchestrator` + shared claim-by-id + `wtm-recovery` (§11.4, §11.6) |
| 4 | `4871d88` | `/healthz` + `/readyz`, maintenance middleware, emergency guard (§4.6, §11.8, §11.9) |
| 5 | `10c0939` | External status mapping `queued/preparing/processing/ready/failed` (§4.5, §11.10) |
| 6 | `f08f825` | API enqueue after commit in tryon/ai/wardrobe endpoints (§11.5) |
| 7 | `ed1aa2e` | `app.tasks.*` one-shot cron wrappers (§11.7) |
| 8 | `6fd9578` | Container images: api / rembg-worker / orchestrator (§11.11) |
| 9 | `cf87a0c` | GitHub Actions build (GHCR) + gated Heroku deploy (§11.12) |
| 10 | `94a0e04` | Azure Container Apps Bicep IaC (§11.13) |
| 11 | `a8a886f` | Cloudflare route plan — not applied (§11.14) |

## Design highlights

- **Postgres stays authoritative (§4.2).** Queue messages are wake signals only (no PII); all claims use `for update skip locked` + a lease (`locked_at`) + authoritative `attempt_count`. Credit spend/refund idempotency is DB-enforced (`credit_transactions.unique(user_id, ref)`); new unique indexes stop duplicate output rows.
- **rembg → one enrichment handoff → orchestrator**, so the cutout reveal never waits on tagging/embedding. `bg_worker.process_item` (combined) preserved for the DO bridge.
- **Recovery** re-signals stale rows (duplicate-safe) and poisons exhausted ones with idempotent refund; it never queries Azure Queue (§4.2).
- **Backward compatible (owner clarification #4):** new `state` field added alongside the unchanged legacy `status`; maintenance/emergency off by default; `/v1/health` preserved; combined worker + `app.cron.*` + `docker-compose.yml` untouched.
- **Runtime DSN:** `db.py` is pooler-agnostic (`statement_cache_size=0` works for both), so **Session Pooler 5432** is selected purely by the deploy-time `CONNECTION_STRING` env (Phase 4) — no runtime found requiring 6543.

## Tests & results (§11.15)

- **Backend suite: 625 passed, 2 skipped** (isolated venv, `pytest -q`) — **+45 tests** over Phase 1's 580. New coverage: queue validation/versioning, exact-job claim, duplicate-signal & terminal no-op, queue-send failure, stale recovery, attempt-limit/poison, rembg→enrichment handoff, kind routing, status mapping (old+new), maintenance mode, health/readiness, legacy entrypoint compatibility, cron wrappers. Idempotent deduction/refund covered by the unchanged `test_credits` (still green).
- **Lint:** `ruff check` clean on all new code.
- **Images:** api builds at **461 MB**; rembg/orchestrator Dockerfiles `--check` clean (full builds run in Phase 4 CI).
- **Bicep:** `az bicep build` clean — 13 resources, no warnings.
- **Workflows:** both YAML files parse; `ci.yml` untouched.
- **Migration 0044:** applied to a throwaway PG17 + idempotent re-apply verified.

## Cost-impact check

**Zero.** No cloud resource created, no prod deploy, migration 0044 NOT applied to Tokyo. Local Docker/PG containers were throwaway.

## Deviations / notes

- **CI `ruff format --check`** inherits pre-existing main-branch format drift (unrelated to this migration). Green CI needs a one-time `ruff format .` fixup — a founder decision (not done here to avoid unrelated churn).
- **ACA API version `2024-10-02-preview`** is required to set the locked `pollingInterval`/`cooldownPeriod` and the KEDA scaler managed identity.
- **rembg model verification** is presence+non-empty (`test -s u2net.onnx`); a strict checksum pin is a hardening TODO.
- **`app.cron.community`** remains unscheduled (Phase 0 finding) — deliberately NOT added to the Azure schedule.
- New deps: `azure-storage-queue`, `azure-identity` (both MIT, lazy-imported, in `LICENSES.md`).

## Unresolved risks

- Migration 0044 unique-output indexes assume no pre-existing duplicate `job_id` rows (true on the fresh Phase 3 restore; verified none in Phase 1 data).
- Cron UTC schedules in Bicep are provisional (`§13.3` finalizes them with evidence in Phase 4); Azure schedule jobs stay disabled until Phase 4 to avoid duplicate execution with DO.

## Rollback state

DigitalOcean intact and serving production unchanged (combined worker, crons, compose all untouched). All Phase 2 work is additive on the migration branch. Nothing to roll back.

## Secret scan

Full Phase 2 diff (`98df3c3..HEAD`) scanned for JWT/`sk-`/DSN-cred/private-key/AWS-key patterns: **clean**. Bicep/params/workflows carry secret **names** only.

## Next approval phrase

```
APPROVED PHASE 2
```
