# Retention & Monetization — deployment order and rollback

Covers migrations **0073–0076**, the backend services that read them, the cron
job they add, and the app release that surfaces them.

**Environment:** prod is Heroku `wtm-api-prod` + Azure ACA Jobs + Supabase US.

⚠ `OPS_RUNBOOK.md` still describes the pre-migration DigitalOcean droplet
(`ofelia`, `docker compose exec`). That host was decommissioned — see
`docs/migration/MIGRATION_STATE.md`, which is the current infrastructure truth.
The runbook is left as-is rather than rewritten here: correcting it is its own
piece of work, and quietly editing it as a side effect of this project would
make it unclear which document was ever reviewed.

---

## The single most important property

**Every feature in this project is OFF, and every configuration value defers to
the code default.** Applying all four migrations to production changes nothing a
user can see and nothing a user is charged. That is deliberate and it is what
makes each step below independently safe to stop after.

Concretely, after 0073–0076 are applied and the backend is deployed:

| | value |
|---|---|
| standard render | 1 credit (`STD_COST`) |
| HD render | 4 credits (`HD_COST`) |
| AI Enhance | 4 credits (`AI_ENHANCE_COST`) |
| free lifetime renders | `FREE_TRYON_TRIAL_CREDITS` (3) |
| Pro / Pro Max | $8.99 / $15.99, 75 / 150 credits — read from `public.plans`, untouched |
| `topup_40` | untouched |
| trial | disabled |
| rollover | disabled |
| every new `feature_*` flag | `false` |

Nothing in this project may change any of those without an explicit decision.

---

## 1. Migrations (deploy first)

Apply in order through the existing reviewer-gated `migration-deploy` workflow.

| file | adds | risk |
|---|---|---|
| `0073_render_cost_ledger.sql` | 12 nullable columns on `ai_usage_log`, 3 on `tryon_results`, 4 indexes, 1 view | none — all additive, no rewrite, no lock beyond a catalog update |
| `0074_style_memory.sql` | `style_memory_profiles`, `style_memory_signals` + RLS | none — new tables |
| `0075_planner_events_and_moods.sql` | `mood_plans`, `style_events` + RLS | none — new tables |
| `0076_monetization_config.sql` | `monetization_config`, `experiment_assignments`, `monetization_events` + RLS + 13 config rows | none — new tables; every seeded value is `null`/`false` |
| `0077_ai_consent_audit_history.sql` | `user_privacy_consent_events` + RLS + a guarded backfill | none — new table; the consent table the gate reads is untouched |

All four are idempotent and re-runnable. **No backfill is required or
performed.** Existing `ai_usage_log` rows keep null in the new columns, which
reads correctly as "written before the ledger was extended".

Verification after apply:

```sql
-- every new flag exists and is OFF
select key, enabled from public.feature_flags where key like 'feature_%v2'
   or key like 'feature_style_memory%' or key in ('feature_mood_planner_v2','feature_event_planner');

-- every render/allowance key defers to code
select key, value from public.monetization_config order by key;

-- RLS is on, with policies, on all six user tables
select c.relname, c.relrowsecurity, count(p.polname)
  from pg_class c left join pg_policy p on p.polrelid = c.oid
 where c.relname in ('style_memory_profiles','style_memory_signals','mood_plans',
                     'style_events','experiment_assignments','monetization_events')
 group by 1,2;
```

---

### ⚠ The AI consent version bump — read before deploying

This release raises `CURRENT_AI_CONSENT_VERSION` from **1 to 2**, which forces
every existing account to accept the AI try-on disclosure once more. Two
consequences follow, and both are deliberate:

1. **Deploy the backend and ship the app together.** The client sends the
   version whose disclosure it displayed. A build that still shows the v1 copy
   sends `1`, which the server now REFUSES with a typed 422 ("Please update
   Wear The Mood to continue with AI try-on") rather than storing an
   unsatisfiable grant. Refusing is the correct behaviour — nobody can consent
   to terms they were never shown — but it means **AI try-on stops working for
   users who have not updated**, until they do. Everything else in the app is
   unaffected.

   If that is not acceptable for a staged rollout, hold the backend bump until
   the new build is broadly adopted: with the server still on v1, the new app
   (which sends `2`) would ALSO be refused, so the two must move together and
   the only safe orderings are "both old" or "both new".

2. **Nothing is deleted.** The bump does not touch historical consent. 0077
   adds an append-only event log and backfills it from the current rows first,
   so the v1 acceptances remain provable after every user re-grants at v2.

Verify after deploy:

```sql
-- every existing account now reads as granted-but-stale, and will be re-asked
select consent_version, count(*) from public.user_privacy_consents
 where consent_type = 'ai_personal_image_third_party_processing'
 group by 1;

-- the backfill represented them in history before anyone re-granted
select source, action, consent_version, count(*)
  from public.user_privacy_consent_events group by 1,2,3;
```

## 2. Backend (deploy second)

The backend is **backward compatible in both directions**, which is what makes
the ordering forgiving:

* **New backend + old migrations.** `load_config` catches `UndefinedTableError`
  and falls back to the compiled constants, so an API released before its
  migration still prices correctly. Covered by
  `test_missing_config_table_falls_back_to_code_defaults`.
* **Old backend + new migrations.** The new tables are simply unread.

Deploy through the `migration-deploy` workflow (the local Heroku token is dead —
see `docs/` note on that). It deploys the API dyno only; the ACA Jobs and the
worker image are separate.

**The worker image must also be rebuilt** — `tryon_worker.py` now writes the
extra ledger columns. It is safe to lag: `_log_usage` passes null for anything a
caller does not supply, so an old worker against the new schema writes exactly
the rows it always did.

### New endpoints (all additive, all under `/v1`)

```
GET    /v1/style-memory                      always readable
GET    /v1/style-memory/signals              always readable
POST   /v1/style-memory/signals              gated: feature_style_memory
PATCH  /v1/style-memory                      gated: feature_style_memory
POST   /v1/style-memory/personalization      always allowed
POST   /v1/style-memory/reset                always allowed (deletion right)
POST   /v1/tryon/results/{id}/feedback       verdict stored always; learning gated
GET    /v1/plans/mood/latest                 always readable
POST   /v1/plans/mood                        gated: feature_mood_planner_v2
GET    /v1/events                            always readable
POST   /v1/events                            gated: feature_event_planner
PATCH  /v1/events/{id}                       gated: feature_event_planner
DELETE /v1/events/{id}                       always allowed (deletion right)
GET    /v1/monetization/config               always readable
POST   /v1/monetization/events               always allowed
```

`POST /v1/privacy/ai-consent` changed behaviour: it now requires
`consent_version` to EQUAL the server's required version. Previously a lower
version was stored as sent. See the consent-bump note above.

Two changed responses, both **additive optional fields** an old client ignores:

* `GET /v1/tryon/{job_id}` → `result_id`
* `GET /v1/tryon/results` → `outcome`

### Environment variables

**None added.** Everything new is database configuration.

---

## 3. Cron job (deploy third, optional)

`event-reminders` (`app.tasks.event_reminders`, hourly at :40) is only needed
once `feature_event_planner` is turned on. Until then it is pure cost with no
effect, so creating it can wait.

⚠ **Do NOT apply `infra/azure/main.bicep` wholesale.** It would rewrite every
existing job and has broken production before. Create this one job directly,
copying the image and env from an existing job:

```bash
az containerapp job show -g <rg> -n wtm-daily-push --query "properties" > /tmp/daily.json
# create event-reminders with the SAME image, secrets and env, command:
#   python -m app.tasks.event_reminders
# schedule: "40 * * * *"  (keep it disabled until the flag is on)
```

---

## 4. App release (deploy last)

The app is safe against every backend state:

* a 404 from a flag-gated write is treated as "the feature is off" and is
  silent;
* `/v1/monetization/config` failing leaves the render gate hidden and the
  paywall unchanged;
* the pressure ledger swallows its own failures — a paywall never fails to open
  because a bookkeeping row could not be written.

Build with the usual `--dart-define-from-file=env/prod.json`.

---

## 5. Enabling anything (a separate, deliberate decision)

Recommended order, one at a time, verifying between each:

1. `feature_style_memory` — signals begin accumulating. Nothing user-visible
   except the Settings row and the screen behind it.
2. `feature_style_memory_feedback` — Keep it / Not me appears on the result
   screen. This is the one that starts producing keep-rate data.
3. `feature_mood_planner_v2` — the free planning loop.
4. `feature_event_planner` — then create the cron above.
5. `feature_personalized_home_v2` — Home composition changes. Highest visual
   blast radius; enable last and watch Home load time.

**Not to be enabled without an explicit pricing decision from the founder:**

* `feature_render_gate_v2` — changes how many free renders a user gets.
* `feature_credit_economics_v2` — changes what HD costs (4 → 2).
* `feature_credit_rollover_v2` — changes credit expiry semantics.
* `feature_paywall_v2` — changes paywall composition.

Even then, the render gate needs BOTH the flag AND either a configured
`free_render_lifetime_limit` or an `experiment_assignments` row; neither alone
does anything. That is intentional (`test_free_limit_unchanged_when_only_*`).

---

## 6. Rollback

Every layer rolls back independently, and none of them requires a migration to
be reversed:

| symptom | action | effect |
|---|---|---|
| any new feature misbehaving | set its `feature_flags.enabled = false` | surface disappears on the next flag refresh; data is kept |
| render gate showing wrongly | `feature_render_gate_v2 = false` | free allowance returns to `FREE_TRYON_TRIAL_CREDITS` |
| costs wrong | `feature_credit_economics_v2 = false` | legacy 1/4 mapping returns immediately |
| paywall pressure too aggressive | raise `paywall_cooldown_hours` in `monetization_config` | takes effect on the next config read; no release |
| ledger writes failing | no action needed | `_log_usage` failures are already non-fatal to a render |
| event reminders spamming | `feature_event_planner = false` | the cron sends nothing on its next run |

The migrations themselves need no rollback: dropping the new tables would be the
only "undo", and leaving them in place with every flag off is indistinguishable
from never having applied them.

---

## 7. What this project deliberately did NOT do

Documented so the next person does not go looking for it:

* **No pricing change.** No product id, price, allowance or entitlement was
  touched. `test_no_price_or_allowance_is_written` enforces this against the
  migration files themselves.
* **No FASHN routing change.** The current provider routing, quality mode and
  fidelity gate are untouched — §21 asks for an experiment only if both branches
  are production-valid, and the repository's own quality work is the newer
  truth. The cost ledger now records `endpoint`, `mode` and `quality_state` per
  render, which is the measurement such an experiment would need first.
* **No photo-quality gate.** §20 asks for a lean one; the existing pipeline
  already refuses unusable inputs at moderation and at the provider with
  actionable messages, and adding a second client-side judge risks blocking
  valid photos. Deferred with the evidence rather than half-built.
* **No calendar integration, no web checkout, no new payment provider, no MMP,
  no referral changes.** Out of scope per §43/§45.
* **No credit rollover implementation.** The flag and the config keys exist;
  the granting logic does not. Enabling `feature_credit_rollover_v2` today is a
  no-op — deliberately, because rollover changes a liability and needs its own
  economics review (§8.4).
