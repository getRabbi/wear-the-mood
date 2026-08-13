# iPhone QA — release 1.0.21, try-on coverage build

**TestFlight 1.0.21 (26)** — Codemagic build #15, `main` @ `7dd53b2`, produced
with `PRE_DEVICE_VALIDATION=true`, uploaded to App Store Connect 2026-08-13
08:46 UTC ("UPLOAD SUCCEEDED with no errors").

This build supersedes the one covered by `IPHONE_TESTFLIGHT_QA.md` (1.0.21 (25),
`release/1.0.21` @ `21f402a`). **That document is still the authority for the
local-cutout device matrix in its §2** — run it first, or alongside; nothing here
replaces it.

> **This pass has not been performed.** It cannot be: driving a physical iPhone is
> not something the release automation can do. Everything below is written to be
> executed by the owner, in order, on the device.

---

## 0. Build identity

| | |
|---|---|
| TestFlight | **1.0.21 (26)** — auto-continued from the previous (25) |
| Codemagic build | #15, `ios-release`, mac_mini_m2, 14 min, all 19 steps green |
| Git SHA | `7dd53b2` (main, PR #15 merged) |
| Backend | `wtm-api-prod` release **v41**, `/readyz` commit `7dd53b2` |
| Admin console | `wtm-admin` **v8** |
| Verifier | `PRE_DEVICE_VALIDATION=true` — **NOT RELEASE APPROVED** until §1 of `IPHONE_TESTFLIGHT_QA.md` §2 is recorded |

Server flags are shared with Android and are currently on: `feature_discover`,
`feature_discover_stories`, `feature_shopping`.

---

## 1. Notification lifecycle (`3840747`)

The fix: the app asks the OS whether to prompt, rather than trusting a flag it
stored on the device. The failure it removes is a re-login showing the
permission explainer again to someone who already granted it.

- [ ] Fresh install, sign in
- [ ] Enable notifications when asked; accept the OS prompt
- [ ] Sign out
- [ ] Sign in again as the same user
- [ ] **The explainer does not appear a second time**
- [ ] Settings → notification preferences still reflect what was chosen
- [ ] Deny the OS prompt on a second account, then re-login → the CTA offers to
      open iOS Settings (not a dead toggle)

---

## 2. Newsroom (`c05a1f6`)

- [ ] Open Newsroom; open **three different publishers**
- [ ] Each opens in the in-app reader, not Safari
- [ ] A publisher that redirects (http → https, or a syndication hop) still loads
- [ ] Back returns to the feed with scroll position intact
- [ ] **No stale "unsafe link" snackbar** carried over from a previous article
- [ ] An article that genuinely fails shows a retry, and retry works

---

## 3. Try-on history (`028b1f0`)

- [ ] Profile → Try-On History is reachable
- [ ] It lists past renders
- [ ] Delete one; it disappears immediately
- [ ] Force-quit the app and relaunch
- [ ] **The deleted item does not return**

---

## 4. Discover (`b7166ab`)

- [ ] Discover has a healthy card inventory — no collapsed or half-empty rails
- [ ] Scroll to the bottom; pagination loads more without a gap
- [ ] The bottom navigation does not obscure the last row
- [ ] Picked for You and All Picks both render real products

---

## 5. Shopping try-on coverage — the new controls

This is the section the release exists for. It needs the admin console open on a
laptop and the phone in hand at the same time.

**Set-up.** In the console (`wearthemood.com/mood-ops-console-7x9`), pick a
merchant you are willing to assert rights for — or create a controlled one. Do
**not** license AliExpress PL unless that is a decision you are making
deliberately.

### 5a. Rights alone do not switch anything on

- [ ] Merchants → store → **Image rights = Licensed** (tick the acknowledgement,
      record a basis and reference)
- [ ] Coverage still reads **off**
- [ ] On the phone, pull-to-refresh Discover → **no TRY ON appears**

### 5b. ALL

- [ ] Coverage → **All eligible products** → confirm the count in the dialog
- [ ] Phone: refresh → **TRY ON appears** on that store's eligible products
- [ ] Tap TRY ON → the mirror opens with the product as the garment
- [ ] Complete a render → it succeeds
- [ ] Result screen offers **View Product** and **Shop at Store**, and both open
      the right product

### 5c. One product excepted

- [ ] Console → that product → **Product try-on = Off**
- [ ] Phone: refresh → **TRY ON is gone from that product only**
- [ ] Other products from the same store still show it

### 5d. SELECTED

- [ ] Console → store → Coverage = **Selected products only**
- [ ] Phone: refresh → **TRY ON disappears everywhere for that store**
- [ ] Console → Products → tick two → **Enable try-on**
- [ ] Read the result message — it reports how many could not become eligible
- [ ] Phone: refresh → **only those two show TRY ON**

### 5e. Emergency shutdown

- [ ] Console → store → Coverage = **Off**
- [ ] Phone: refresh → **no TRY ON anywhere for that store**
- [ ] **Shop at Store, Save, and browsing still work** — this is the check that
      proves coverage is not a catalogue kill switch
- [ ] Console → back to **Selected products only**
- [ ] Phone: refresh → **the two products you picked are on again**, without
      re-selecting them

### 5f. The stale-client rejection (the important one)

- [ ] Phone: open a product that currently shows TRY ON, and **stop there** —
      do not refresh the screen again
- [ ] Console: set that product's **try-on to Off** (or the store to Off)
- [ ] Phone: on the same, now-stale screen, tap **TRY ON** and complete the flow
      through to Generate
- [ ] **The render is refused.** Expected: "This product is not available for
      try-on."
- [ ] **No credit is deducted** — check the credit balance before and after
- [ ] Nothing appears in Try-On History for the refused attempt

### 5g. Rights are authoritative

- [ ] Console: set a product **try-on = On** but **rights = Unknown**
- [ ] The product readiness panel says **not eligible**, reason *image rights*
- [ ] Phone: refresh → **no TRY ON** on that product

---

## 6. Regression sweep

- [ ] Product Details, Search, Saved all open and show consistent TRY ON state
      (a product either shows it everywhere or nowhere)
- [ ] Giveaway list + detail
- [ ] Community feed
- [ ] Inbox
- [ ] A deep link into a product opens the product
- [ ] Closet try-on (a wardrobe garment) still works and is unaffected by any
      coverage setting

---

## 7. Record the result

If §2 of `IPHONE_TESTFLIGHT_QA.md` (the local-cutout device matrix) passes,
record it so the release verifier clears:

```
python scripts/verify_local_cutout_release.py \
  --record-device-evidence ios \
  ...   # see docs/bg/LOCAL_FIRST_BG_OPERATIONS.md §6 for the exact fields
python scripts/verify_local_cutout_release.py --target ios-production --config app/env/prod.json
```

Only a clean run **with no flags** clears an iOS release. Until then this build is
explicitly not release-approved, by design.
