# Discover — manual QA checklist (Android, dev)

The pass a human has to do. Everything here is either impossible to automate or
was deliberately not automated: real pixels, a real browser, a real network
dropping out, and a real app being killed.

**Build:** `E:\dopplefit\artifacts\wear-the-mood-discover-dev-qa.apk`
SHA-256 `aa979a4badda6eb86f7f959648a40f5b6d31ff382f937d5cc943f0f25bfed6b2`

This build points at **dev**, not production. That is deliberate — the Discover
tables and flags exist only in dev. Nothing you do here can affect production.

Mark each line **PASS** / **FAIL** / **N/A**. A FAIL needs the screen, the
steps, and a screenshot.

---

## 0. Before you start

Discover is served by the dev backend on your laptop, so three things must be
running. Skip any one and the app looks broken for the wrong reason.

- [ ] **Backend up.** In PowerShell: `E:\dopplefit\backend\serve.ps1`
      Leave it running. It prints `Uvicorn running on http://127.0.0.1:8000`.
- [ ] **Phone tunnelled.** `E:\SDK\platform-tools\adb.exe reverse tcp:8000 tcp:8000`
      Re-run this after every unplug or reboot — the tunnel does not survive.
- [ ] **App installed.** `E:\SDK\platform-tools\adb.exe install -r -t "E:\dopplefit\artifacts\wear-the-mood-discover-dev-qa.apk"`

      ⚠️ **Use a phone or emulator that is NOT carrying a release build.** This
      APK is debug-signed, so a device holding a release-signed install refuses
      it with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, and the only way past that
      is an uninstall — which permanently wipes that device's Saved Looks,
      local collections, recent searches and session. Do not do that to a real
      install. (Verified on `ab617080` / M2007J20CG, which holds 1.0.20+23.)
- [ ] **Signed in.** A **dev** account — sign-in goes to the dev Supabase
      project, so your production account does not exist here. If you have none,
      use `New here? Create an account` on the sign-in screen; it signs up
      against dev.

      Prefer **email + password**. `GOOGLE_WEB_CLIENT_ID` is empty in
      `env/dev.json`, so `Continue with Google` falls back to the web OAuth flow
      in Chrome, and that flow needs this build's **debug** signing SHA-1
      registered against the dev OAuth client. If Google sign-in bounces, that
      is the reason — it is not a Discover defect. See
      `docs/ANDROID_SIGNING_KEYS.md`.
- [ ] Sanity: open Discover. Products appear. If the grid is empty, the backend
      or the tunnel is down — fix that before recording any FAIL.

**What "correct" looks like for the store link.** The dev catalog is seeded, and
its merchants point at `wearthemood.com` standing in for a retailer. A correct
`Shop at Store` opens the browser at
`https://wearthemood.com/?wtm_dev_ref=wtm-seed-…&aff=wtm-…`. **The query string
is the pass criterion**, not the page — you are checking that the app opened the
one URL the backend validated, with the product ref and the affiliate tag on it.

---

## 1. Home

- [ ] Greeting, plan and credit balance render as before.
- [ ] Mood slider, Try-On Studio, Smart Closet, AI Stylist, Outfit Maker and
      Today's Look all still open and work.
- [ ] **`Shop Your Mood`** appears where `Inspiration for You` used to be, with a
      compact preview of real products — not placeholders.
- [ ] `View all` opens Discover.
- [ ] The **old `Giveaways / Offers / Newsroom` shortcut row is gone** from Home.
- [ ] The full Discover Stories rail is **not** duplicated on Home.
- [ ] Home scrolls smoothly, no jank on the preview row.
- [ ] Tapping a preview product opens Product Details, and Back returns to Home
      at the same scroll position.

## 2. Navigation

- [ ] The bottom bar reads **HOME · DISCOVER · AI ORB · INBOX · PROFILE**.
- [ ] The Discover item uses a compass-style glyph, not the old Social one.
- [ ] The central AI orb behaves exactly as before.
- [ ] Switching tabs and coming back preserves Discover's scroll position.

## 3. Discover Stories

- [ ] The rail renders portrait cards, **not** circular avatar bubbles.
- [ ] Roughly 2.4–2.8 cards are visible on a phone; the first is not larger.
- [ ] At most six cards. No empty or placeholder card.
- [ ] Card text is never clipped, in any card.
- [ ] Unseen cards carry the gradient ring; seen ones a neutral border.
- [ ] Tap a card → the Story Viewer opens.
- [ ] Tap right → next story. Tap left → previous.
- [ ] Swipe down, and the close button, both exit.
- [ ] **Android back button** exits the viewer, and does not leave the app.
- [ ] Closing returns you to Discover at the same scroll position.
- [ ] A story's primary CTA lands on the right destination (Giveaway → the
      giveaway, Offer → the offer, Newsroom → the article).
- [ ] Reopen the app: a story you viewed is still marked seen.
- [ ] With the backend stopped, opening a story shows a retry and **does not**
      mark it seen.

## 4. Product feed

- [ ] The grid is two columns on a phone.
- [ ] Each card shows image, brand, title (max two lines), price, at most one
      match reason, a heart, and a `Try On` affordance only when compatible.
- [ ] No card shows a full description, all sizes, all colours, delivery detail
      or more than one badge.
- [ ] Scrolling loads more without duplicating a product you already passed.
- [ ] The feed does **not** reorder itself while you scroll.
- [ ] After four products there is at most one full-width module, and it is
      never empty.
- [ ] Pull-to-refresh works and does not jump your scroll position.
- [ ] Images load progressively — skeletons first, never a blank page or a bare
      spinner.

## 5. Search and filter

- [ ] The header search icon opens the product search screen.
- [ ] Typing a term returns matching products; the keyboard never covers the
      field or the results.
- [ ] A term with no matches shows an empty state, not an error.
- [ ] Recent searches appear on return, and can be cleared.
- [ ] The filter sheet opens with Category, Price, Size, Colour, Brand/store,
      Try-On Ready and Discount.
- [ ] Applying filters shows the compact `Filters · N` indicator — **no**
      permanent chip row on Discover.
- [ ] `Reset` clears them.
- [ ] Open a product from filtered results and come back: **the filters and the
      scroll position are still there.**

## 6. Saved

- [ ] The header heart opens Saved.
- [ ] Tap a heart on a card → it fills; the same product shows as saved on
      Product Details, and vice versa.
- [ ] Unsave removes it from Saved.
- [ ] Double-tapping the heart quickly does not create two entries.
- [ ] A saved product that is out of stock **still appears**, labelled — it does
      not silently vanish.
- [ ] Saved survives a kill and restart.

## 7. Product Details

- [ ] Order: gallery → brand → title → price → sizes → colours → try-on
      compatibility → match reason → description → delivery region → affiliate
      disclosure → similar products → sticky action bar.
- [ ] The disclosure reads *"Wear The Mood may earn a commission from eligible
      purchases."*
- [ ] A try-on-ready product shows `Try On` + `Shop at Store`; a non-try-on
      product shows `Save` + `Shop at Store`.
- [ ] Similar products are listed and open in place.
- [ ] A product that is gone opens and **explains itself** — it does not 404 or
      show a blank screen — and offers alternatives.
- [ ] Back returns to the feed at the same position.

## 8. Variants

- [ ] Sizes and colours are listed for a product that has them
      (`Black silk slip dress` has three variants).
- [ ] A variant that is out of stock is shown as unavailable, not hidden and not
      selectable as if it were fine.
- [ ] Prices shown are per variant where the variant has its own price.
- [ ] `৳`, `$` and `¥` products all format correctly — the seeded catalog has
      BDT, USD and JPY, and **JPY must show no decimal places**.

## 9. Shopping Try-On

> This spends real credits and makes a real AI render. Do it deliberately, and
> check the balance before and after.

- [ ] From Product Details, `Try On` enters the **existing** Mirror flow — the
      same body-photo/model step you already know.
- [ ] Only the one product being tried on is applied; no closet items leak in.
- [ ] Generation shows progress, then reveals the result.
- [ ] Credits decrement **once**, on success.
- [ ] Force a failure (turn the backend off mid-render): **credits are refunded**
      and the product context is kept.
- [ ] A plain closet try-on, started from the Mirror as usual, behaves exactly as
      it did before — no product, no shop actions.

## 10. Result actions

- [ ] The result offers `Shop at Store` as primary, with Save Look secondary.
- [ ] `Shop at Store` opens the browser with the correct `wtm_dev_ref` and `aff`
      query string.
- [ ] Save Look saves it.
- [ ] Back / Retry / Adjust all still work.

## 11. Kill and restart restoration

- [ ] Start a shopping try-on, **kill the app from the task switcher mid-render**,
      reopen it.
- [ ] The look is in Saved Looks.
- [ ] Opening it offers **View Product** and **Shop at Store** — the origin
      outlived the process.
- [ ] `View Product` opens the right product with a live price.
- [ ] `Shop at Store` from the restored look opens the correct URL.
- [ ] Do the same with an ordinary closet look: it shows **no** shop actions.

## 12. Offline cache

- [ ] Open Discover with the network on, then enable airplane mode and reopen it.
- [ ] The first page of cached products is shown, with an offline indicator.
- [ ] Nothing crashes; no infinite spinner.
- [ ] Turn the network back on and pull to refresh: fresh content replaces the
      cache.
- [ ] Tapping a product while offline shows a clear error rather than a blank
      screen.

## 13. Price and stock changes

With the app open on Product Details, change the row in dev and pull to refresh:

```bash
cd E:\dopplefit\backend
.\.venv\Scripts\python.exe -c "import psycopg,os;from dotenv import dotenv_values;from app.core.config import pick_migration_dsn;dsn,_=pick_migration_dsn(dotenv_values('.env'));c=psycopg.connect(dsn,autocommit=True);c.execute(\"update public.products set price_minor = 199900 where external_id='wtm-seed-d1'\")"
```

- [ ] The new price appears after refresh — Product Details revalidates rather
      than trusting the card.
- [ ] Set `stock_status='out_of_stock'`: the product reports itself unavailable
      and `Shop at Store` is not offered.
- [ ] Save a product, then lower its price: Saved shows the price-drop state.
- [ ] Re-run `python scripts/seed_discover_catalog.py --destination-host wearthemood.com`
      afterwards to put the catalog back.

## 14. Affiliate launch

- [ ] **Product Details → `Shop at Store`** opens the system browser (or a Custom
      Tab) at `https://wearthemood.com/?wtm_dev_ref=…&aff=…`.
- [ ] **Try-On result → `Shop at Store`** does the same.
- [ ] **Restored Saved Look → `Shop at Store`** does the same.
- [ ] Return to the app: you are still on the screen you left, not on a blank
      page.
- [ ] Tap `Shop at Store` **once**, then check exactly one row was recorded:
      ```sql
      select count(*), max(clicked_at) from public.affiliate_clicks;
      ```
- [ ] Tap it twice fast: still **one** new row, not two.
- [ ] Stop the backend and tap `Shop at Store`: a clear non-blocking error with a
      retry, the browser does **not** open an empty tab, and you stay on Product
      Details.
- [ ] Sanity that the guard is live — set a merchant's agreement to paused and
      tap Shop: the button reports the store is unavailable rather than opening
      anything.
      ```sql
      update public.merchant_affiliate_config set status = 'paused';
      -- and put it back
      update public.merchant_affiliate_config set status = 'ok';
      ```

## 15. Giveaways — must be unchanged

- [ ] Reachable from Discover (story card, feed module, or both).
- [ ] The list loads and a giveaway opens.
- [ ] **Create Giveaway is still there** in the Giveaway hub and still works —
      image limits, validation, the lot.
- [ ] Request → accept/reject still work.
- [ ] The secret pickup chat still opens and sends.
- [ ] An owner can still delete their own listing.
- [ ] Nothing about giveaways looks or behaves differently from before Discover.

## 16. Offers

- [ ] Reachable from Discover.
- [ ] Today's offers load and open.
- [ ] An offer's link opens correctly.
- [ ] No flashing-red sale styling.

## 17. Newsroom

- [ ] Reachable from Discover.
- [ ] Articles load and open; the feed shows no full article text.
- [ ] Closet-match suggestions inside an article still work.

## 18. Inbox

- [ ] The Inbox tab opens.
- [ ] Giveaway conversations are still listed and still open.
- [ ] A push notification deep-links to the right place (giveaway, chat,
      product, story) and, if the content is gone, lands somewhere safe rather
      than blank.

## 19. Community stays hidden

- [ ] There is **no** public community feed.
- [ ] There is **no** create-post / Share a Look button anywhere.
- [ ] There are no `For You / Following / New / Near You` filters.
- [ ] No community activity notifications arrive.
- [ ] An old `/social` link or notification does not crash — it lands on Discover
      or a safe read-only screen.
- [ ] Create Giveaway is still reachable (the composer being hidden must not have
      taken it with it).

## 20. Android back button

- [ ] Back from Product Details → the feed, same position.
- [ ] Back from the Story Viewer → Discover.
- [ ] Back from Search / the filter sheet → Discover.
- [ ] Back from Saved → Discover.
- [ ] Back on the Discover root → the previous tab or a normal exit, never a
      blank screen and never a loop.
- [ ] Back after returning from the browser → you are where you left off.

## 21. Narrow phone

Test on the smallest phone you have, or `adb shell wm size 320x640`
(reset with `adb shell wm size reset`).

- [ ] No horizontal overflow stripes anywhere on Discover.
- [ ] Story card text is not clipped.
- [ ] Product cards do not overflow; the two-column grid still fits.
- [ ] The Product Details sticky action bar fits both buttons.
- [ ] The bottom bar and safe-area spacing are intact.

## 22. Tablet

- [ ] The grid uses 3–5 columns depending on width, and cards do not stretch into
      banners.
- [ ] More story cards are visible, at a similar size — not oversized.
- [ ] Portrait **and** landscape both work.
- [ ] Content is centred with a sensible maximum width rather than stretched edge
      to edge.

## 23. Large text

Settings → Display → Font size at maximum (or `adb shell settings put system font_scale 2.0`,
reset with `1.0`).

- [ ] No clipped story or product titles.
- [ ] No overflow on Product Details.
- [ ] The filter sheet stays usable.
- [ ] Buttons stay tappable and labels stay readable.
- [ ] Also check with reduced motion enabled: animations are subdued, nothing
      breaks.

## 24. Slow internet

`adb shell settings put global captive_portal_mode 0` is not enough — use the
emulator's network throttle, or a genuinely poor connection.

- [ ] Discover shows skeletons, never a blank screen and never a bare spinner.
- [ ] Products appear progressively rather than all at once.
- [ ] A failed load shows a retry and keeps whatever content is already valid.
- [ ] Tapping through fast during loading does not crash or double-navigate.
- [ ] A slow `Shop at Store` shows the opening state and does not fire twice.

## 25. Logout and account switch

- [ ] Log out from Profile. Discover no longer shows personalised content, and
      nothing crashes.
- [ ] Log back in as the **same** user: Saved and recently viewed are still
      there.
- [ ] Log in as a **different** user: Saved is that user's, not the previous
      one's. **This is the important one** — a saved list leaking across accounts
      is a privacy bug, not a cosmetic one.
- [ ] Recent searches and recently viewed do not carry over between accounts.
- [ ] Delete-account still works and still removes the account.

---

## Reporting

For every FAIL: the screen, exact steps, what you expected, what happened, a
screenshot, and the device + Android version. For anything involving the store
link, include the **full URL from the browser address bar**.

When the pass is done, record the result in
[`DISCOVER_FINAL_HANDOFF.md`](DISCOVER_FINAL_HANDOFF.md) §5 and tick the device
lines in [`DISCOVER_ROLLOUT.md`](DISCOVER_ROLLOUT.md) §6.
