# PAYMENTS_SETUP.md — Pro / Pro Max + top-ups (RevenueCat → backend)

The backend is **data-driven**: the RevenueCat webhook maps `event.product_id` →
a row in the **`plans`** table (`play_product_id` / `app_product_id`) → tier +
`monthly_credits`. So the only rule is: **the store product IDs must match the
`plans` seed.** No code change to add/adjust products later — it's a `plans` UPDATE.

## 1. Product IDs the stores must use (must match `plans`)
| Product | Type | Price | `plans.tier` | Credits |
|---|---|---|---|---|
| `pro_monthly` | auto-renewing subscription | $8.99/mo | `pro` | 75 |
| `pro_max_monthly` | auto-renewing subscription | $15.99/mo | `pro_max` | 150 (HD) |
| `topup_40` | one-time / consumable | $4.99 | `topup_40` | 40 (top-up) |

*(Seeded by migration `0022`. To change later, e.g. raise Pro to 120 at FASHN
volume pricing, just `update public.plans set monthly_credits=120 where tier='pro';`
— no deploy.)*

## 2. Google Play (first launch)
1. Play Console → **Monetize → Subscriptions**: create `pro_monthly` ($8.99) and
   `pro_max_monthly` ($15.99), each with a base monthly plan. Optionally a 14-day
   free trial offer.
2. Play Console → **In-app products**: create the consumable `topup_40` ($4.99).
3. Use these **exact** product IDs (they map straight to `plans`).

## 3. RevenueCat
1. Add the Play app + the **Play service credentials**.
2. **Products**: import `pro_monthly`, `pro_max_monthly`, `topup_40`.
3. **Entitlements**: one entitlement (e.g. `premium`) attached to both
   subscriptions. (The backend derives tier from `product_id`, not the entitlement
   name, so the entitlement name is informational.)
4. **Offerings**: a `default` offering with a **Pro** package and a **Pro Max**
   package (the paywall reads these). Top-up is purchased outside the offering.
5. **App `app_user_id` = the Supabase user id** — the Flutter app calls
   `Purchases.logIn(supabaseUserId)` so the webhook's `app_user_id` is our UUID.
   **This is mandatory**: the webhook ignores non-UUID `app_user_id`s.

## 4. Webhook (RevenueCat → backend)
- RevenueCat → **Integrations → Webhooks**:
  - **URL:** `https://api.wearthemood.com/v1/billing/webhook`
  - **Authorization header:** the value of `REVENUECAT_WEBHOOK_AUTH` (set the same
    secret in the droplet `backend/.env`). The endpoint rejects any other value.
- The backend handles the full lifecycle:
  | Event | Effect |
  |---|---|
  | `INITIAL_PURCHASE` / `RENEWAL` / `PRODUCT_CHANGE` | set tier + **grant** the period's credits (SET, no rollover; idempotent per period) |
  | `CANCELLATION` (auto-renew off) | **stays entitled** until expiry, status `canceled`, no grant |
  | `BILLING_ISSUE` | **grace** — entitled while the store retries, no grant |
  | `EXPIRATION` / `SUBSCRIPTION_PAUSED` / `REFUND` | revoke (status `expired`) |
  | `NON_RENEWING_PURCHASE` (`topup_40`) | record `top_up_purchases` + add to the **top-up** bucket (survives reset), idempotent per store transaction |

## 5. App Store (at iOS launch — later)
Create the same product IDs in App Store Connect, add the App Store app to
RevenueCat, and set `plans.app_product_id` if the IDs differ from Play. No backend
change.

## 6. Verify (after the backend deploy)
- Sandbox-buy `pro_monthly` → `select tier,status,current_period_end from
  public.user_subscriptions where user_id='<uid>'` shows `pro`; `select balance
  from public.credits` shows 75; a `grant` row in `credit_transactions`.
- Buy `topup_40` → `topup_balance` += 40, a `top_up_purchases` row.
- Cancel in sandbox → still `is_premium` until expiry; let it expire → `expired`.
- Re-deliver the same webhook event → **no double credit** (idempotent ref).
