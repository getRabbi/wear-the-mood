# Discover — final handoff

What is finished, what was proven and how, and the short list of things only a
human with a phone can still answer. Companion to
[`DISCOVER_ROLLOUT.md`](DISCOVER_ROLLOUT.md) (the runbook) and
[`DISCOVER_USER_QA_CHECKLIST.md`](DISCOVER_USER_QA_CHECKLIST.md) (the device
pass).

**Date:** 2026-08-06 · **Branch:** `fix/enhance-quality-giveaway-state-notifications`
· **App version:** 1.0.20+24 · **Flutter:** 3.44.1

> **Production is untouched.** No production Supabase, Heroku, Azure, merchant
> data, affiliate credential or feature flag was read for writing or changed.
> Migrations 0053–0056 remain **unapplied on prod** and every Discover flag
> there is still absent/OFF. Nothing here starts a rollout.

---

## 1. State of the work

All seven implementation phases were already complete on this branch
(`c602b7d` … `5a46d77`). This pass added no features. It enabled the experience
in dev, exercised it over real HTTP, fixed two genuine defects that the live run
exposed, and produced a testable build.

### Commits added in this pass

| Commit | What |
|---|---|
| `6b769bd` | **fix** — undeliverable products no longer reach the feed |
| `bae9545` | **feat** — the dev seed can point at a host that actually resolves |
| `d61f8f5` | **feat** — `affiliate_click_failed`, the missing half of the §40 alert |
| `76b08ee` | **docs** — this file, the QA checklist, and the runbook update |

Ten code/test files, +375/−11. No dependency, schema, route or contract changed.

### Why each fix exists

**`6b769bd` — undeliverable products.** `build_where` only checked country
availability when a country was resolved, and a brand-new user has none: the
app takes its region from the server's answer, which is null until shopping
preferences exist. A product whose `country_availability` and its merchant's
`shipping_countries` are both populated and share nothing can be delivered to
nobody, and it reached that user's feed — where Product Details then opened
saying it ships nowhere while `Shop at Store` still worked. The deliverability
check is now an always-on clause, independent of who is asking. An empty array
on either side still means "unrestricted", so only a genuine contradiction is
suppressed. Found by the live HTTP run, not by any test.

**`bae9545` — a resolvable dev destination.** The committed seed points at
`example.test`, which does not resolve *by design* — so the one thing no test
can prove, that tapping `Shop at Store` opens a real page in the system
browser, could not be checked at all. `--destination-host` is off by default
and takes a bare hostname and nothing else; a scheme, port, path, wildcard or
userinfo is refused, because the value becomes an allow-list and an allow-list
that widens from the command line is not one. The override *replaces* the
fixture domain rather than joining it, so no unowned domain is left permanently
allow-listed. Nothing about validation changed.

**`d61f8f5` — `affiliate_click_failed`.** The runbook alerts on "affiliate
redirect failures above 1% of click attempts" (§40), but nothing client-side
counted the failures — only the backend warn log, which cannot see a browser
that refused the URL. The rate had no numerator. The event fires at all three
Shop entry points with a typed `failure_code`: `unavailable`, `unreachable`, or
`launch_failed`. The last is separate on purpose — the backend produced a valid
destination and *already recorded the click*, so a device with no browser must
not read as merchant configuration drift. It is its own event rather than a
property on `affiliate_click`, because a failure counted as a click would
inflate the denominator it is measured against and the failure rate could only
ever fall.

---

## 2. Dev environment as left

**Supabase dev:** `jdrdnwkttcqfitwzlysn` (ap-southeast-2). Migrations 0053–0056
applied. **Prod (`ghzabbceoaoertatkjyg`) has none of them.**

### Feature flags — exact values, read back from `public.feature_flags`

| Key | Value |
|---|---|
| `feature_discover` | **true** |
| `feature_discover_stories` | **true** |
| `feature_shopping` | **true** |
| `feature_legacy_home_discover` | **false** |
| `feature_community_posting` | **false** |
| `feature_community_notifications` | **false** |

`feature_community` has **no row** in dev, and an absent key reads as OFF, so
the public community feed stays hidden. Nothing else was touched.

### Catalog

29 seeded products · 22 servable · **21 reaching the feed**. The gap of one is
the deliverability fix above: `wtm-seed-neg-country` is servable but ships
nowhere, and is now correctly suppressed. Three merchants (two approved, one
deliberately unapproved), 6 variants, 2 affiliate configurations.

### Affiliate destination

Dev clicks resolve to **`https://wearthemood.com/?wtm_dev_ref=<external-id>&aff=<tag>`**.

`wearthemood.com` is the project's own Cloudflare Pages site — a controlled
HTTPS host that already existed and already answers 200. **Nothing was deployed
to it and no production system was changed**; only two rows in the *dev*
`merchants` / `merchant_affiliate_config` tables name it. It stands in for a
retailer so a human can watch the browser open. Every protection is intact:
HTTPS-only, default port only, no userinfo, and the allow-list is exactly
`['wearthemood.com']`, so a lookalike is still refused.

To reproduce, or to go back to the non-resolvable fixture:

```bash
cd backend
python scripts/seed_discover_catalog.py --destination-host wearthemood.com  # resolvable
python scripts/seed_discover_catalog.py                                     # fixture
```

---

## 3. What was proven — live HTTP, 94/94

Real requests over the wire against the dev backend (`uvicorn app.main:app`,
dev `.env`, dev Supabase) with a real Supabase JWT from a disposable dev
account created through the same Auth Admin API path
`scripts/create_owner_admin.py` uses. Direct SQL was used only to build
fixtures and to confirm what a request actually wrote. No credential appears in
any commit or log.

| Area | Checks | Result |
|---|---|---|
| Authentication | 8 | Every route 401s anonymously and on a garbage bearer |
| Product feed | 5 | Items, minor-unit money, no destination/ref/template leak, schema version |
| Pagination | 4 | Keyset cursor, no duplicates across a full walk, count matches SQL, malformed cursor → 400 |
| Facets | 5 | Categories/sizes/colors present, unapproved merchant absent, try-on + discount reported |
| Search & filters | 4 | Term match, empty result is a page not an error, `try_on_ready` excludes `pending`, `discounted` |
| Product Details | 10 | Servable/shoppable/stale reported, variants, delivery countries, out-of-stock opens and explains, malformed UUID → 404 never 500 |
| Similar | 2 | Same category, excludes the anchor, never returns a suppressed product |
| Save / unsave | 8 | 204s, idempotent double-save is one row, feed reflects it, unavailable saves still listed, unknown product → 404 |
| Country | 7 | JP and BD sets match SQL, saved preference beats a stale query param, invalid code rejected |
| Suppression | 2 | All 8 negative records absent from the feed; unapproved merchant contributes nothing |
| Affiliate click | 24 | See below |
| Interactions | 3 | 204, replayed `client_event_id` writes one row, unknown type rejected |
| Try-on origin | 3 | A shopping job reports its product/merchant/placement; a withdrawn product leaves no dangling origin |
| Flags ON/OFF | 6 | `/v1/flags` matches the table; `feature_shopping=false` closes **8/8** catalog routes server-side; ON restores |

### The affiliate click, in detail

- Missing `Idempotency-Key` → 400.
- One intentional click → **exactly one** `affiliate_clicks` row; the stored row
  keeps the host and the merchant-side ref, **never the tagged URL**.
- Retry with the same key → same `click_id`, **no second row**.
- **The same key from a different user → 409, and wrote nothing.** Cross-user
  replay is impossible, not merely unlikely.
- Unapproved merchant, out-of-stock product, malformed UUID → 404.
- Refused with 502 and **no destination returned**: lookalike host
  (`wearthemood.com.evil.test`), bare off-domain host, subdomain-suffix trick
  (`notwearthemood.com`), absolute `javascript:`, `data:`, plain `http`,
  non-default port, userinfo.
- A *relative* ref containing `javascript:` or `&aff=attacker#frag` is
  **neutralised**, not rejected: it is percent-encoded into the query on the
  allow-listed host and cannot overwrite the affiliate tag. That is the designed
  behaviour, and it is now asserted.
- A **paused** merchant agreement stops the click (502) and Product Details
  reports `shoppable=false` up front.
- **The destination the API handed out was fetched and returned HTTP 200.**

### Command results

| Command | Result |
|---|---|
| `ruff check .` | **PASS** — all checks passed |
| `ruff format --check .` | **PASS** — 271 files already formatted |
| `pytest -q` | **PASS** — 1098 passed |
| `dart format --output=none --set-exit-if-changed .` | **PASS** — 603 files, 0 changed |
| `flutter analyze` | **PASS** — no issues found |
| `flutter test` | **PASS** — 1262 passed |
| `flutter build apk --debug --dart-define-from-file=env/dev.json` | **PASS** |
| `python scripts/verify_local_cutout_release.py --target ci` | **PASS** — all 38 invariants hold |

---

## 4. The QA build

| | |
|---|---|
| Path | `E:\dopplefit\artifacts\wear-the-mood-discover-dev-qa.apk` |
| SHA-256 | `aa979a4badda6eb86f7f959648a40f5b6d31ff382f937d5cc943f0f25bfed6b2` |
| Size | 261,354,064 bytes |
| Build | `flutter build apk --debug --dart-define-from-file=env/dev.json --dart-define=API_BASE_URL=http://localhost:8000` |

Debug, because only the debug manifest allows cleartext to a local backend. The
`API_BASE_URL` override matches `app/run.ps1`: the committed `env/dev.json`
holds `http://10.0.2.2:8000`, which is the *emulator's* host alias and does not
resolve on a phone. `localhost:8000` plus `adb reverse` works on both.

**It will show an empty, signed-out app without the backend running** — it
points at dev on purpose, because the Discover flags and the catalog only exist
there. Startup steps are the first section of the QA checklist.

`artifacts/` is git-ignored; the APK is a build output, not a committed file.

---

## 5. Status of every remaining item

| Item | Status |
|---|---|
| Dev flags set to the exact six values and read back | **PASS** |
| Live HTTP smoke: feed, pagination, facets, search, details, similar | **PASS** |
| Live HTTP smoke: save/unsave, invalid UUID, country, suppression | **PASS** |
| Live HTTP smoke: affiliate click, idempotent retry, conflicting key | **PASS** |
| Live HTTP smoke: anonymous vs authenticated | **PASS** |
| Live HTTP smoke: flag ON behaviour and OFF fallback | **PASS** |
| Affiliate destination resolvable, protections intact | **PASS** |
| Backend lint / format / tests | **PASS** |
| Flutter format / analyze / tests / debug APK | **PASS** |
| Repo release-invariant check | **PASS** |
| Responsive layout at every §41 breakpoint | **PASS** (automated, `wtm_rollout_test.dart`) |
| Kill-switch restores the safe fallback | **PASS** (server-side proven live; client-side by test) |
| QA APK produced and hashed | **PASS** |
| **PostHog runtime events** | **NOT VERIFIED — external blocker** |
| **iOS compile check** | **NOT VERIFIED — external blocker** |
| **Device install / launch smoke** | **NOT VERIFIED** — no device attached to ADB |
| **Real paid AI render (shopping try-on end to end)** | **NOT VERIFIED** — deliberately not run |
| **Everything in the user QA checklist** | **NOT VERIFIED** — needs a human and a phone |

### Blocker 1 — PostHog has no key, anywhere

`POSTHOG_API_KEY` is empty in `app/env/dev.json`, empty in `app/env/prod.json`,
and **empty in the Heroku production config** (`wtm-api-prod`). Codemagic lists
it as optional in the `app_prod_config` group. There is no dev key to configure,
so none was invented and none was hard-coded.

`analyticsProvider` returns `NoopAnalytics` whenever the key is empty
(`app/lib/core/analytics/analytics_provider.dart`), so every `track` call is a
safe no-op and the abstraction is covered by the passing suite — including three
new assertions on `affiliate_click_failed`. What cannot be verified is that any
event *arrives*: `discover_open`, story impression/open/action, `product_open`,
`product_save`/`product_unsave`, `try_on_start`/`complete`/`fail`,
`affiliate_click` and `affiliate_click_failed` are all emitted by code and all
land in a no-op sink.

**To unblock:** create a PostHog project, put its key in `app/env/dev.json`
(git-ignored) and rebuild. It is a prerequisite for rollout stage 3 either way.

### Blocker 2 — iOS cannot be compiled against this code yet

`codemagic.yaml` already has a safe, signing-free `ios-compile-check` workflow,
and it needs no change for this work: the three new pub dependencies resolve to
`shared_preferences_foundation` and `path_provider_foundation` (both already in
the iOS plugin registrant) plus `visibility_detector`, which is pure Dart.

The blocker is not iOS. **This branch has not been pushed** — `origin` is still
at `823f7b7`, before the first Discover commit, so every line of the feature
exists only on this machine. Codemagic builds from the remote, so triggering it
now would compile code that does not contain the feature. It was therefore not
triggered, and iOS is **NOT VERIFIED**.

**To unblock**, push the branch and start the workflow:

```bash
git push origin fix/enhance-quality-giveaway-state-notifications
```

Then in Codemagic → app `wear-the-mood` → **Start new build** → workflow
**`ios-compile-check`** → branch
`fix/enhance-quality-giveaway-state-notifications`. It runs
`flutter build ios --release --no-codesign` on a `mac_mini_m2`: no signing, no
TestFlight, no App Store, nothing published beyond a completion email. Note the
workflow's own trigger is `push` to `main` only, so it must be started by hand
for a feature branch.

---

## 6. Known limitations carried into rollout

Unchanged from the runbook, plus one:

- No per-user percentage bucketing. `feature_flags` is global on/off, so "5%"
  means a small closed group on a build pointed at a non-production project.
- PostHog inert until a key exists (above).
- Shopping try-on has still never run against a real render or a real merchant.
  The *origin plumbing* is proven over HTTP — a job carries its product,
  merchant and placement, and a withdrawn product leaves no dangling link — but
  no image has been generated through the shopping path.
- Home issues a product-feed request when `feature_shopping` is on, even for
  users who never open Discover.
- `merchant_affiliate_config` is default-deny by having no RLS policies. A
  future migration adding a permissive policy would leak affiliate tags — flag
  it on any RLS sweep.
- The dev affiliate destination is the marketing site, not a store. The pass
  criterion on a device is **the query string in the address bar**, not the page
  content.

---

## 7. Rollback

Nothing here needs undoing to ship, and nothing here reached production. If dev
should go back to the pre-Discover experience:

```sql
-- dev only (jdrdnwkttcqfitwzlysn)
update public.feature_flags set enabled = false
 where key in ('feature_discover', 'feature_discover_stories', 'feature_shopping');
update public.feature_flags set enabled = true
 where key = 'feature_legacy_home_discover';
```

Effective on the next flag fetch — Discover's pull-to-refresh or a cold start.
No release, no store review.

To undo the seeded catalog, or just its destination:

```bash
cd backend
python scripts/seed_discover_catalog.py --clear   # removes exactly the wtm-seed-* rows
python scripts/seed_discover_catalog.py           # back to the example.test fixture
```

To undo this pass's commits (they are local only — `origin` is still at
`823f7b7`, before Discover began):

```bash
git revert 76b08ee d61f8f5 bae9545 6b769bd   # keep history
git reset --hard 5a46d77                     # or discard this pass outright
```

Schema rollback is unnecessary — no migration was added or applied in this pass.
The 0053–0056 rollback SQL is in the runbook if a migration itself ever needs
withdrawing.

---

## 8. Next steps, in order

1. Run [`DISCOVER_USER_QA_CHECKLIST.md`](DISCOVER_USER_QA_CHECKLIST.md) on a
   phone with the QA APK.
2. Set a dev PostHog key and confirm events arrive.
3. Push the branch and run `ios-compile-check`.
4. Only then consider production: apply 0053–0056 to prod, load a **real**
   merchant feed (never the seed), configure `merchant_affiliate_config` with
   real credentials, and walk the runbook's staged enablement from stage 0.
