# Discover — rollout and rollback runbook

Operating document for enabling the Discover redesign (spec §30, §40).
Everything here is reversible from the `feature_flags` table without a binary
release. **Read the whole file before flipping anything.**

Status: all code is merged on
`fix/enhance-quality-giveaway-state-notifications`. **Migrations 0053–0056 are
applied to DEV (`jdrdnwkttcqfitwzlysn`, ap-southeast-2). Production
(`ghzabbceoaoertatkjyg`) has none of them. Every Discover flag is OFF in every
environment.**

---

## 1. Migrations — apply these first, in order

Discover reads tables that do not exist yet. Enabling a flag before its
migration is applied produces a 404 from the API (by design) or an empty
surface — not a crash, but not a feature either.

| # | File | What it adds |
|---|---|---|
| 0053 | `supabase/migrations/0053_discover_catalog.sql` | `merchants`, `products`, `product_variants`, the six Discover flags (all FALSE) |
| 0054 | `supabase/migrations/0054_discover_saves_and_interactions.sql` | `saved_products`, `product_interactions`, `shopping_preferences` |
| 0055 | `supabase/migrations/0055_discover_affiliate_clicks.sql` | `merchant_affiliate_config` (service-role only), `affiliate_clicks` |
| 0056 | `supabase/migrations/0056_tryon_shopping_source.sql` | shopping-origin columns on `tryon_jobs` |

0053 and 0054 were applied to **dev** during Phase 3.1; 0055 and 0056 on
2026-08-06, verified with 39 schema/RLS checks. **All four are unapplied on
production.**

There is no migration-history table in this repo. The record is the ordered
files here plus the schema itself, so "has 0056 been applied?" is answered by
looking for `tryon_jobs.source_kind` — not by a version row. Every migration is
idempotent, so a re-run is safe, but check first rather than relying on that.

```bash
# from backend/, against the environment's own .env
python scripts/apply_sql.py ../supabase/migrations/0055_discover_affiliate_clicks.sql
python scripts/apply_sql.py ../supabase/migrations/0056_tryon_shopping_source.sql
```

Every one is additive and idempotent — new tables and nullable columns only.
Re-running is safe. Nothing existing is altered, so there is no data migration
and no downtime.

### Seeding a catalog (dev/staging only)

```bash
python scripts/seed_discover_catalog.py
```

Writes 29 prefixed products across three merchants, including one negative
record per suppression rule, plus redirect configuration so the outbound click
can actually be exercised. The script refuses a production-looking DSN without
an explicit long-form override.

**Production needs a real merchant feed, not the seed.** A production catalog
also needs rows in `merchant_affiliate_config` — without them every Shop tap
answers 502 by design.

---

## 2. Flags — what each one turns off

Every risky path and the single flag that disables it (§40 requirement).

| Flag | Default | Disables |
|---|---|---|
| `feature_discover` | FALSE | The whole Discover tab. OFF → tab 1 renders the existing Community surface, exactly as today. **The master kill switch.** |
| `feature_discover_stories` | FALSE | The Stories rail and viewer only. Discover keeps its header and product feed. |
| `feature_shopping` | FALSE | The catalog: product feed, search, filters, Saved, Product Details, the affiliate click, and shopping Try-On. Enforced **server-side too** — the API answers 404 regardless of what the client believes. |
| `feature_legacy_home_discover` | FALSE | Inverted: TRUE **restores** the old Home `Giveaways / Offers / Newsroom` row. |
| `feature_community_posting` | FALSE | The public create-post composer. Does **not** affect Create Giveaway. |
| `feature_community` | FALSE (existing) | The public community feed and its filters. |

Two properties worth knowing:

- **`feature_shopping` is independent of `feature_discover`.** The catalog can
  be dark-launched, or pulled after launch, without taking the Stories rail
  down with it.
- **The Home shortcut row also returns whenever `feature_discover` is OFF**,
  regardless of the legacy flag. Giveaways, Offers and Newsroom live in the
  Discover branch; removing the row while Discover is off would leave all three
  unreachable.

---

## 3. Staged enablement

Each stage is one flag. Sit at each for long enough to read the dashboard
before moving on.

| Stage | Flags on | Watch for |
|---|---|---|
| 0. Dark | none | Nothing changes. Confirms the migrations broke nothing. |
| 1. Internal | `feature_discover` | Tab renamed, Community hidden, Giveaway/Offers/Newsroom still reachable from Discover. |
| 2. Stories | `+ feature_discover_stories` | Rail renders, viewer navigates, seen state persists. |
| 3. Catalog | `+ feature_shopping` | Feed paginates, Saved works, Product Details revalidates, **the outbound click opens a real retailer**. |
| 4. Widen | same flags, more users | 5% → 20% → 50% → 100%. |

The app has no per-user percentage bucketing. `feature_flags` is a global
on/off, so "5%" today means a small closed group on a build pointed at a
staging project — **not** a percentage rollout on production. Add PostHog
feature flags (already a dependency) before claiming a percentage rollout.

Before stage 3, verify by hand on a device:
- a product opens, and its price matches the merchant's site
- Shop at Store opens the **correct retailer page** in the system browser
- an `affiliate_clicks` row appeared with the right product and merchant
- the destination carries the affiliate tag

---

## 4. Rollback

In order of blast radius, smallest first.

```sql
-- Catalog misbehaving; keep Discover and the rail.
update public.feature_flags set enabled = false where key = 'feature_shopping';

-- Stories rail misbehaving; keep Discover and the catalog.
update public.feature_flags set enabled = false where key = 'feature_discover_stories';

-- Full stop: back to the pre-Discover app.
update public.feature_flags set enabled = false where key = 'feature_discover';
update public.feature_flags set enabled = true  where key = 'feature_legacy_home_discover';
```

Effect is immediate on next flag fetch — the app invalidates on Discover's
pull-to-refresh and on cold start. No release, no store review. Covered by a
test: `wtm_rollout_test.dart` flips the flags mid-session and asserts the
Community surface comes back.

Schema rollback is only needed if a migration itself is the problem:

```sql
drop table if exists public.affiliate_clicks;
drop table if exists public.merchant_affiliate_config;
alter table public.tryon_jobs
  drop column if exists source_kind,
  drop column if exists source_product_id,
  drop column if exists source_merchant_id,
  drop column if exists source_placement,
  drop column if exists source_campaign_id;
```

`products` / `merchants` / `saved_products` hold real data once seeded — do not
drop those without a considered decision.

---

## 5. Monitoring

§40 asks for a minimal dashboard before broad enablement. The events exist in
the app; **PostHog is inert until a key is set** (`POSTHOG_API_KEY` is empty in
both `app/env/dev.json` and `app/env/prod.json`), so none of this records
anything yet. Setting that key is a prerequisite for stage 3.

| Signal | Event / source | Alert when |
|---|---|---|
| Discover load failure | `discover_feed_failed` | > 2% of `discover_open` |
| Feed pagination failure | `feed_load_more` vs error logs | any sustained rise |
| Affiliate redirect failure | backend `fashionos.discover` warn, `affiliate redirect rejected` | > 1% of click attempts |
| Merchant/domain validation | same log, `reason=host_not_allowed` | **any** occurrence — it means configuration drift |
| Try-On failures | `try_on_fail` + existing refund path | above the pre-Discover baseline |
| Giveaway regressions | existing giveaway events | any drop vs baseline |
| Stale catalog suppression | `products` where `last_synced_at` is old | rising count = a dead importer |
| Unknown feed/story types | client-side skip | any — an older build is being served newer content |

Crash-free sessions and next-day return come from Sentry and PostHog
respectively; both are already wired.

---

## 6. Manual QA — what tests cannot cover

Automated at every breakpoint in §41 (`wtm_rollout_test.dart`): small phone
320dp, large phone 430dp, 7-inch 600dp, 10-inch 800dp, tablet landscape,
phone landscape, plus 1.3× and 2.0× text scaling. Layout overflow fails the
build. That is **not** the same as a device run.

Still outstanding, and only a human can do it:

- [ ] Android device: full Discover → product → Shop at Store → retailer
- [ ] Android device: product → Try On → generate → result → Shop at Store
- [ ] Android device: kill the app mid-render, reopen, find the look in Saved Looks, confirm View Product / Shop return
- [ ] Android device: failed generation refunds credits
- [ ] iOS compile check on Codemagic (monthly cadence per CLAUDE.md §21)
- [ ] iPad-class portrait and landscape
- [ ] Reduced motion enabled
- [ ] Slow network, then airplane mode, then return — offline cache behaviour
- [ ] Screen reader pass over Discover, Product Details and the story viewer
- [ ] Giveaway create → request → accept → chat, unchanged
- [ ] Inbox still receives Giveaway conversations
- [ ] Push deep links still resolve

---

## 7. Known limitations at rollout time

- No per-user percentage bucketing (see §3).
- PostHog key empty → every analytics acceptance criterion is unverifiable in
  production until it is set.
- Shopping Try-On has never run against a real render or a real merchant.
- Home issues a product-feed request when `feature_shopping` is on, even for
  users who never open Discover.
- `merchant_affiliate_config` is default-deny by having no RLS policies. A
  future migration that adds a permissive policy would leak affiliate tags —
  flag this on any RLS sweep.
