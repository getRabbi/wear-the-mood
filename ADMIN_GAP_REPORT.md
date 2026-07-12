# ADMIN_GAP_REPORT — Admin ↔ App Sync Audit

**Date:** 2026-07-13 · **App state audited:** `main` @ `4c022d5` (schema through migration 0037)
**Admin baseline:** console built + deployed 2026-06-27 against schema ≤ 0030 (0031/0032 are admin-side RPCs).
**New since that baseline:** 0033–0035 (Premium AI Studio: `ai_jobs`, `generated_images`, `tryon_model_presets`, `tryon_avatars`, wardrobe AI columns, `tryon_jobs.model_source`), 0036 (credits RLS lockdown, HD → Pro Max), 0037 (giveaway pickup chat + widened claim statuses), the WTM Atelier shell cutover (default app since 2026-07-09), and two new report subject types (`giveaway`, `giveaway_chat`).

**Sources triangulated:** `supabase/FASHIONOS_BASELINE.sql` + migrations 0001–0037 · all 29 FastAPI routers + crons/workers · Flutter data layer (25 repositories, freezed models, WTM `app/lib/ui/*`) · all of `admin-web/src` (14 pages, 8 action modules, 7 DAL modules, auth boundary, export route).

**Headline:** the security invariants from `BUILD_PROMPT_ADMIN_PANEL_FINAL.md` are **intact** — no P0 security regressions found. The gaps are moderation blind spots: every entity shipped after 2026-06-27 (AI Studio outputs, giveaways, pickup chats) is invisible and un-actionable in the console, and the report queue cannot resolve the two newest — and highest-abuse — subject types.

Effort scale: **XS** <1h · **S** ≈half-day · **M** 1–2 days · **L** multi-day.

---

## Bucket 1 — Missing visibility

| # | Sev | Entity | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| 1.1 | P1 | `ai_jobs` | No admin list/detail. Credit-reserving async jobs (enhance/catalog, 1–4 credits) cannot be inspected for credit disputes or failure triage. | `supabase/migrations/0033_premium_ai_studio.sql:52`; no reference in `admin-web/src` | `admin_list_ai_jobs` RPC + `/ai-jobs` page (filter: type, status, user; paginated), linked from user detail. | M |
| 1.2 | P1 | `generated_images` | No admin view at all — including rows with `report_count > 0`. Users can self-report an unsafe AI output and **nobody can ever see it**. | `0033:84–95`; report bump `backend/app/routers/v1/ai_studio.py:246–260`; no reports-table row is created | Reported-images queue (`report_count > 0` first) + full list with preview + takedown (see 2.4/3.2). | M |
| 1.3 | P1 | `giveaways`, `giveaway_claims` | Public UGC with images and P2P meetups; no admin list, detail, or claim visibility. | `0020_giveaways.sql`; zero `giveaway` matches in `admin-web/src` | `/giveaways` page: list (status/search/paginated) + detail with claims + moderation actions (2.3). | M |
| 1.4 | P1 | `giveaway_pickup_chats`, `giveaway_chat_messages` | Reported chats freeze their transcript for §19 review — but there is **no transcript viewer**. Review is impossible. | `0037:36–86`; no admin reference | Transcript view reachable only from a report row (participants-only privacy holds: admin views via audited RPC). | M |
| 1.5 | P2 | `tryon_jobs` / `tryon_results` | Dashboard shows only `failed_tryons_today`; no per-user job list for "my credits vanished" disputes. Partially mitigated by the credit ledger. | `admin-web/src/lib/dal/dashboard.ts:22` | Per-user try-on job list on user detail (id, status, hd, model_source, credits). | S |
| 1.6 | P2 | `feature_flags` | The app's real kill-switches (`feature_giveaway_chat`, `feature_community`, …) are toggled by SQL on the droplet. Settings only exposes 3 `app_config` keys — a different table. | `backend/app/routers/v1/flags.py`; `admin-web/.../settings/page.tsx:29–46` | Flags card in Settings: list `feature_flags`, audited toggle RPC. | S |
| 1.7 | P2 | `ai_usage_log` | CLAUDE.md §14 calls AI cost runaway "risk #1"; the console has no cost view. | §14; no admin reference | Daily cost rollup RPC (by provider/model/day) + dashboard card with spend-today. | M |
| 1.8 | P2 | `top_up_purchases`, `plans`, global `credit_transactions` | Billing ops blind spots: per-user ledger exists but no global adjustments/purchases view; plan config (incl. `hd_allowed`) invisible. | `admin-web/src/lib/dal/billing.ts` (per-user only) | Global ledger tab (recent `credit_transactions` w/ reason filter), read-only plans + top-ups list. | S–M |
| 1.9 | P2 | `daily_guides`, `offers`, `quizzes`/`quiz_questions`, `challenges`, `news_items` | Ops-authored content with no authoring UI (SQL-only today). | no admin references | Author/edit forms per entity — **founder to prioritize which ones matter**; each follows the seed-post form pattern. | M each |
| 1.10 | note | `wardrobe_items`, `outfits`, `tryon_photos`, `consents`, `taste_signals`, `referrals`, `device_tokens`, user `notifications` | No coverage — **recommend keeping it that way** (private/biometric-adjacent data, §10). Counts-only if ever needed. | — | No action. | — |
| 1.11 | note | `tryon_avatars` | Dormant by design (schema+RLS only, zero code references). Nothing to cover yet; wire into admin when the feature is built. | `0033:102–117` | Track in the drift checklist. | — |

## Bucket 2 — Missing actions

| # | Sev | Entity | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| 2.1 | P1 | `reports` (subject `giveaway`, `giveaway_chat`) | The app files `subject_type='giveaway'` and the backend `'giveaway_chat'`, but the 0027 queue RPC resolves only `post/comment/user` → these rows render with **NULL target preview and NULL reported user**, so the ban/strike/hide buttons never appear. Only dismiss/note work. The two newest abuse surfaces are un-moderatable. | app: `giveaway_detail_screen.dart:147`; backend: `giveaways.py:898`; RPC: `0027:90–105`; UI branches: `reports/page.tsx:28,42,108–109`; stale type: `dal/reports.ts:15` | Extend `admin_list_reports` (new RPC version) to resolve both types (giveaway → owner + title/image; chat → both participants + giveaway); add UI branches + actions (2.2, 2.3). | M |
| 2.2 | P1 | `giveaway_pickup_chats.report_flag` | Set in exactly one place, **cleared nowhere** in the entire codebase. The retention cron skips redaction while it is true — so every reported chat keeps both users' message bodies (meetup places/times, §10 data) **forever**, and the promised "redact once the flag is cleared" can never happen. | set: `giveaways.py:893`; cron guard: `cron/giveaway_chats.py:114`; no other writer (repo-wide grep) | Audited `admin_review_pickup_chat` RPC: *clear flag* (cron then redacts on schedule) or *keep frozen + escalate*; reason required; resolves the linked report. | S |
| 2.3 | P1 | `giveaways` | No hide/close/soft-delete for a live public listing (scam/unsafe-meetup takedowns impossible). Requires 3.1 first. | `0020` (no moderation cols); no admin actions | `admin_hide_giveaway` / `admin_close_giveaway` / `admin_delete_giveaway` (soft) RPCs, wired like posts (list + report-queue). | S (after 3.1) |
| 2.4 | P2 | `generated_images` | No admin takedown. Only the owner can delete (hard delete). | `ai_studio.py:230–243` | `admin_remove_generated_image` (soft, 3.2) + audit; surfaced in the 1.2 queue. | S |
| 2.5 | P2 | `tryon_model_presets` | The one ops-owned content entity (upload image → flip `is_active`) is managed by hand-SQL over SSH; 0035 had to add a safety net against a bad manual activation. | `0033:30–47`, `0035:28–30`; reads: `ai_studio.py:290` | Presets manager page: upload image (reuse seed `maybeUpload`), edit fields, audited activate-toggle that refuses a NULL/empty `image_url`. | M |
| 2.6 | P2 | posts/reports | No bulk actions (e.g. dismiss N reports, hide N posts from one spammer). | `reports/page.tsx`, `posts/page.tsx` (row-only actions) | Checkbox multi-select → one audited bulk RPC per action with per-row audit entries. | M |

## Bucket 3 — Missing data-model support

| # | Sev | Entity | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| 3.1 | P1 | `giveaways` | No moderation columns at all: `status` is lifecycle-only (`available/reserved/claimed/closed`); no `hidden_at`, `deleted_at`, `moderated_by`, `moderation_reason`, `is_seed`. Public read policy has no hidden/deleted filter concept. | `0020:13–28` | Migration 0038: add the standard moderation column set + partial index; backend browse/detail queries exclude hidden/deleted (RLS select stays permissive, backend is the read path — same pattern as posts). | S |
| 3.2 | P2 | `generated_images` | No `status`/`deleted_at`/`moderated_by` — admin takedown (2.4) has nothing to write; `report_count` exists with no queue semantics (no `reported_at`, no resolution state). | `0033:84–95` | Same migration: `status text default 'active'` (`active/removed`), `deleted_at`, `moderated_by`, `moderation_reason`; serve-side filters skip removed rows. | S |
| 3.3 | P2 | `giveaway_pickup_chats` | Chat review outcome has no home: clearing `report_flag` should record who/when/why. | `0037:36–59` | Add `report_cleared_by uuid`, `report_cleared_at timestamptz` (audit log carries the reason); cron logic unchanged. | XS |

## Bucket 4 — Schema drift / stale admin

| # | Sev | Entity | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|---|
| 4.1 | P1* | posts/reports/seed images in admin | Admin renders raw `posts.image_url`; the app/backend now resolve images through `media_assets` (R2 object keys + thumbnails, signed/CDN URLs). While prod `STORAGE_WRITES=legacy` the previews still work; **the moment it flips to `r2`, every new post/giveaway image in admin is a broken key string**. \*Severity: P1 if prod is already `r2`, else scheduled-P1 — **verify `backend/.env` on the droplet first**. | `posts/page.tsx:89–93`, `reports/page.tsx:31–32`; resolver: `social.py:135–137`; gate: `core/config.py:122`, `OPS_RUNBOOK.md:63` | Resolve via `media_assets` inside the list RPCs (prefer thumbnail, public URL for public sectors) so admin never sees a raw key. Do it now — it is forward-compatible with legacy URLs. | S–M |
| 4.2 | P2 | `dal/reports.ts` | `ReportRow.subject_type` typed `"post" \| "comment" \| "user"` — already false at runtime (giveaway/chat rows exist). TypeScript narrowing hides the new cases from every switch. | `dal/reports.ts:15` | Widen the union as part of 2.1; add `default` branches that render unknown types visibly instead of silently. | XS |
| 4.3 | ✔ | — | No dead pages, no references to renamed/removed columns or routes found. `ComingSoon` component is defined but unused. `posts.visibility` exists in the baseline. | repo-wide grep | Nothing to do. | — |

## Bucket 5 — Security / consistency regressions

**No P0 findings.** Verified intact: `requireAdmin`/`requirePermission` re-run in every DAL read, server action, and the export route handler (`require-admin.ts:30–69`, `audit-log/export/route.ts:14–17`); all mutations go through `security definer` RPCs that write `admin_audit_log` in the same transaction; enforcement actions require a reason; the service-role key lives only in `lib/supabase/admin.ts` behind `server-only`; soft delete is the default; RLS on the new 0033/0037 tables is correct (service-role-only writes, owner/participant reads); the 0036 credits client-write hole was already closed.

| # | Sev | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|
| 5.1 | P2 | Zod inconsistency: `sendCampaign`/`cancelCampaign` validate with bare `Number.isInteger`; `setSeedAvatar`, `seedLike`, `toggleSeedEnabled`, `pauseAllSeed`, `deleteAllSeed`, `setAdminStatus` use raw `String()` casts. RPCs still validate server-side — consistency debt, not a vulnerability. | `actions/notifications.ts:34,48`; `actions/seed.ts:92,216–218,266`; `actions/admin.ts:50–51` | Add the missing Zod schemas (mechanical). | XS–S |
| 5.2 | P2 | Generated-image self-reports bypass the `reports` table entirely (counter only) — the safety loop has no reviewable artifact. (Action fix in 1.2/2.4.) | `ai_studio.py:246–260` | Optionally also insert a `reports` row (`subject_type='generated_image'`) so one queue covers everything — decide in D2. | XS |

## Bucket 6 — Optimization opportunities

| # | Sev | Finding | Evidence | Proposed fix | Effort |
|---|---|---|---|---|---|
| 6.1 | P2 | Credits page is per-user lookup only; auditing recent admin adjustments or spend anomalies needs a global view. | `dal/billing.ts:26` | Global recent-transactions tab (reason filter, paginated) — pairs with 1.8. | S |
| 6.2 | P2 | Missing indexes for the new admin queries this report adds: `reports (status, created_at)` for the queue, `generated_images (report_count) where report_count > 0`, giveaway moderation partial index (with 3.1). | 0024 indexes `subject` only | Add in the same migration 0038. | XS |
| 6.3 | ✔ | Dashboard stats already a single RPC; lists already paginated (25/page) with filters; badge head-counts are cheap. | `dashboard.ts`, DAL modules | Nothing to do. | — |
| 6.4 | P2 | No drift guard — this audit was manual and will rot again on the next app update. | — | Phase Z: generate shared row types from the schema, plus a re-runnable drift-check script (see plan). | M |

---

## Prioritized remediation plan

### Phase D0 — verify + P0s *(none open; 30 min)* — ✅ DONE 2026-07-13
- No security regressions to fix. One verification gates severity elsewhere: **SSH to the droplet and check `STORAGE_WRITES` in `backend/.env`** — if `r2`, 4.1 is a live P1 and moves to the front of D1.
- **Verified: prod is `STORAGE_WRITES=legacy`** → 4.1 stays a scheduled fix in D2 (do it before any R2 cutover).

### Phase D1 — restore the moderation loop for the new UGC *(P1: 2.1, 2.2, 2.3, 3.1, 3.3, 1.3, 1.4, 6.2)* — ✅ DEPLOYED TO PROD 2026-07-13 (0038 on dev+prod; api/worker/admin-web rebuilt; prod RPC smoke green; commit `31dff0c`)
1. **Migration 0038** (idempotent): giveaway moderation columns (3.1), chat `report_cleared_by/at` (3.3), new indexes (6.2); new/updated RPCs — `admin_list_reports` v2 resolving `giveaway` + `giveaway_chat` (2.1), `admin_list_giveaways`, `admin_hide/close/delete_giveaway` (2.3), `admin_get_pickup_chat_transcript`, `admin_review_pickup_chat` (2.2) — all audited, reason-required.
2. Admin UI: `/giveaways` list+detail (1.3), report-queue branches for both new types with hide/close/clear-flag/keep-frozen actions, transcript viewer (1.4), widened `ReportRow` type (4.2).
3. Backend: giveaway browse/detail queries exclude hidden/deleted rows.

### Phase D2 — AI Studio visibility + image-drift fix *(P1: 1.1, 1.2; P1*/P2: 4.1; P2: 2.4, 3.2, 5.2)* — ✅ DEPLOYED TO PROD 2026-07-13 (0039 on dev+prod; containers rebuilt, health green; prod smoke: 17 ai_jobs + 13 generated images now visible; commit `9639598`). 5.2 decided: self-reports now also file a `reports` row (`generated_image`), resolved by the queue. 4.1 done in SQL via `admin_public_image` (media_assets `public_url`; no new env var); private R2 signing for AI outputs rides the R2 cutover.
1. Migration: `generated_images` moderation columns (3.2); RPCs `admin_list_ai_jobs`, `admin_list_generated_images` (reported-first), `admin_remove_generated_image`.
2. Admin UI: `/ai-jobs` + reported-images queue with preview + takedown; per-user AI jobs on user detail.
3. Resolve every admin image via `media_assets` in the list RPCs (4.1) — posts, reports previews, seed feed, giveaways.
4. Decide: also file generated-image reports into `reports` (5.2).

### Phase D3 — ops tooling the console was missing *(P2: 1.5–1.8, 2.5, 6.1)* — ✅ BUILT 2026-07-13 (migration 0040 on DEV, smoke green; prod apply + deploy pending approval)
Feature-flags card in Settings (1.6) · try-on model presets manager with image-guarded activation (2.5) · AI cost rollup + dashboard spend card (1.7) · global credit ledger + top-ups/plans read views (1.8, 6.1) · per-user try-on job list (1.5).

### Phase D4 — consistency, bulk, content authoring *(P2: 5.1, 2.6, 1.9)*
Zod everywhere (5.1) · bulk report/post actions (2.6) · authoring UIs for guides/offers/quizzes/challenges/news **in the order the founder actually operates them** (1.9 — ask before building).

### Phase Z — drift guard (make this audit a one-command re-run)
Generate shared row types from the Supabase schema and import them in the admin DAL (renames fail the build, not runtime) · commit a `scripts/admin-drift-check` that diffs app entity usage (tables/report subject types/flags) against admin RPC coverage and prints anything uncovered · add a "new app feature ⇒ admin checklist" (moderation columns + list/detail/actions + audit + report-queue hook) to the repo.

### Definition of done (from the audit prompt)
Every P1 closed (D1+D2); every entity the app can produce is viewable + moderatable with audit-logged actions; no admin query resolves stale schema or raw R2 keys; security invariants still hold; drift check committed and re-runnable.
