# iOS Guest Mode — App Review 5.1.1(v)

**Status:** implemented and tested. **Not deployed, not submitted.** The backend
public read surface must be deployed before the reviewer path works end to end
(see *Deployment* below).

---

## 1. The root cause

The rejection was not "the app is missing a Continue as Guest button". It was
that **nothing in the app was reachable without an account**, at two layers at
once:

1. **Client.** The router redirect in `core/router/app_router.dart` sent every
   signed-out user to `/wtm/auth`. There was no other signed-out destination.
2. **Backend.** Every route under `/v1` carried `Depends(get_current_user)` —
   including `/v1/flags`, `/v1/news` and the whole shop catalog. A signed-out
   client could not read a feature flag, let alone a product.

So a guest button alone would have produced an empty app. Both layers are
addressed.

## 2. Architecture

Guest is an explicit **application state**, never an account. No Supabase
anonymous user, no shadow account, no fake email, no server-side record.

```
AppSessionState = unknown | signedOut | guest | authenticated
```

`unknown` and `signedOut` have exactly the permissions of `guest`: none.
Only `authenticated` may act. A valid session always outranks a stale guest flag.

Enforcement is at four layers, each independently sufficient for the cases it
covers:

| Layer | File | Stops |
|---|---|---|
| UI | `ui/auth/guest_gate.dart` | taps — before any picker, permission, spinner or call |
| Router | `core/router/app_router.dart` + `core/auth/guest_capabilities.dart` | deep links, push routes, stale back-stack |
| Service | `core/auth/auth_required.dart` | direct controller/service invocation |
| Network | `core/network/guest_api_guard.dart` | everything else — one interceptor on the shared Dio |

The network guard is the one that makes the guarantee provable: every repository
shares one `Dio`, so with no session the **only** requests that leave the app are
the public read mirrors. Everything else is rejected before it reaches the wire.

## 3. Platform isolation

`core/platform/platform_capabilities.dart` is the single, injected policy.
`guestModeSupported` is true only for `TargetPlatform.iOS` and not web.

* Android's signed-out landing is still `WtmAuthScreen`, reached by the same
  path, in sign-in mode. No guest button. No new storage read. No new call.
* `GuestSessionController.build()` resolves synchronously to `false` off iOS, so
  Android never even has an `unknown` window to settle.
* The resume path returns before touching anything off iOS.

Because the policy is injected rather than read from the host, **both platforms
are tested from one machine** (`test/guest/platform_isolation_test.dart`,
`test/guest/guest_router_test.dart`).

## 4. Guest capability matrix

Deny-by-default. Anything not listed is locked, including anything added later.

### Allowed
| Capability | Surface |
|---|---|
| View public Home | `/wtm/home` |
| Select / preview a mood | local only, no write |
| Browse Shop / Discover | `/wtm/discover` |
| Search and filter products | `/wtm/discover/search`, `/wtm/discover/browse` |
| Product details | `/wtm/discover/product` |
| Merchant "Shop Now" link | resolved server-side, no click recorded |
| Read Newsroom | `/wtm/newsroom`, `/wtm/newsroom/article`, in-app reader |
| Giveaway info + public rules | `/wtm/giveaways`, `/wtm/giveaways/detail` |
| Legal / privacy / terms | external hosted URLs |
| Try-On explainer | `/wtm/mirror` renders an honest feature preview |
| Closet explainer | `/wtm/closet` renders the feature preview |
| Guest Profile panel | `/wtm/profile` — honest "nothing is saved yet" |

### Denied — requires a real account
Person photo · garment upload · any upload to backend/R2/third party ·
background removal / cutout / temp jobs · closet create/edit/delete · every
try-on mode (2D, AI Couture, Try Look, AI Enhance, Catalog Model Shot) · any AI
job · any AI provider call · photo moderation · every credit operation · try-on
history and private results · outfits and Saved Looks · cloud favourites ·
profile create/edit · like, comment, post, follow, block, message · giveaway
create/enter/edit/delete · push registration · purchases and restores · account
settings and purchase history · anything reached by notification routing,
universal links or debug routes.

## 5. Consent v2 is untouched

Nothing in this work changes `ensureAiConsent`, its version, its storage, its
review screen or its withdrawal path. The sequence is unchanged:

1. Real account → 2. user starts an AI photo feature → 3. just-in-time Consent v2
→ 4. named third-party disclosure → 5. only then is a photo transmitted →
6. declining sends nothing, starts nothing, spends nothing.

Guest Mode sits **before** step 1. A resumed try-on intent lands on the *first
step* of the authenticated flow (`/wtm/mirror`), never on a submit — so the
consent sheet appears in its normal place.

## 6. Post-auth intent

`core/auth/pending_auth_intent.dart` stores a semantic action and, at most, a
**public** resource id (a product or giveaway id — the kind of value that already
travels in a shareable link). Never a photo, a draft, a token or a credit.

`take()` reads and clears atomically, so a resume can only happen once — which is
what makes it impossible to duplicate a save, an entry, a credit or a job.
Cleared on dismissal, sign-out and account deletion.

## 7. Backend

New, additive, read-only: `backend/app/routers/v1/public.py`.

```
GET  /v1/public/flags
GET  /v1/public/discover/products
GET  /v1/public/discover/facets
GET  /v1/public/discover/products/{id}
GET  /v1/public/discover/products/{id}/similar
POST /v1/public/discover/products/{id}/click     # resolves a destination, records nothing
GET  /v1/public/news
GET  /v1/public/news/{id}
GET  /v1/public/giveaways
GET  /v1/public/giveaways/{id}
```

* Not one existing route was relaxed. `test_public_guest_surface.py` asserts that
  every other `/v1` route still requires `get_current_user`.
* No per-user field is computed anywhere: no `saved`, no personalization, no
  ownership, no interaction history, no closet read.
* The public giveaway view is **narrower** than the authenticated one: owner id
  and owner name are redacted.
* No affiliate URL is pre-disclosed; the destination is built server-side and
  validated against the merchant domain allow-list, exactly as on the private
  route.
* Rate-limited per IP, tighter than the authenticated equivalents.

Shared queries were extracted (`list_news_rows`, `news_row`,
`build_public_facets`, `resolve_public_images`) so the public and private routes
run the *same* statement rather than two copies that can drift.

## 8. Deployment

**Nothing has been deployed and nothing has been submitted.** Two ordered steps,
both requiring explicit authorization:

1. **Deploy the backend** (`migration-deploy` workflow — see
   `docs/prod-deploy-traps`). Until `/v1/public/*` is live, a guest build gets
   401s on every read and the guest experience is empty. **This must go first.**
2. **Build and submit iOS.** The app is safe to ship before or after, but is
   only *useful* after step 1.

No migration is required — the public router reads existing tables only.

## 9. App Review notes (draft)

> **Guest access (guideline 5.1.1(v))**
>
> Wear The Mood no longer requires an account to use the parts of the app that
> do not need one.
>
> **Where to find it:** launch the app. The first screen after the splash offers
> three choices — *Create My Wardrobe*, *Continue as Guest*, and
> *Already have an account? Sign In*. "Continue as Guest" is a full-width button
> directly below the primary call to action.
>
> **Available without an account:**
> - Home
> - Shop / Discover: browse the product catalog, search, filter
> - Product details, including opening the retailer's own page
> - Newsroom articles
> - Giveaway listings and their rules
> - Privacy Policy, Terms and support information
> - An explanation of how Virtual Try-On works
>
> **Why the rest requires an account:** the remaining features are not gated for
> commercial reasons — they cannot function without an owner.
> - **Virtual Try-On** generates an image from a photograph of the user's own
>   body. That photo is sensitive personal data. It must belong to an account so
>   it can be stored privately, so the user can review or withdraw their consent
>   to third-party AI processing, and so they can delete it. We will not accept
>   a body photograph from an anonymous session.
> - **Closet / wardrobe** is the user's own clothing, photographed by them.
> - **Credits and subscriptions** are balances; an anonymous balance cannot be
>   restored, transferred or refunded.
> - **Saved products, outfits and looks** are personal collections that sync
>   across the user's devices.
> - **Community and giveaways** are social actions attributable to a person, and
>   giveaway entries have to be verifiable and notifiable.
>
> Tapping any of these as a guest shows a short explanation with the option to
> create an account or dismiss and keep browsing. Dismissing returns the user to
> the same page. No photo is selected, no permission is requested and no data is
> sent before an account exists.
>
> **Reviewer reproduction path:**
> 1. Install and launch.
> 2. Tap **Continue as Guest**.
> 3. Open the Discover tab — products load without a login.
> 4. Use search and the filters.
> 5. Open a product; tap the retailer link.
> 6. Open the Newsroom and read an article.
> 7. Tap Save on a product, or the Closet tab, or Try-On — each explains why an
>    account is needed. Tap **Not Now** to stay in the guest experience.
> 8. Optionally create an account from one of those prompts; the app returns to
>    what you were doing.
>
> There is no reviewer-only mode and no hidden bypass: this is the experience
> every iOS user gets.
