# iPhone TestFlight QA — build 1.0.21 (25)

Codemagic #14, `release/1.0.21` @ `21f402a`, uploaded 2026-08-12 08:01:44 UTC.

Read section 0 before starting. Nothing in this build has ever run on an iPhone.

---

## 0. What is actually at risk here

**Apple Vision has never produced a cutout on physical hardware — not once.**
The encoder defect fixed in `bf945e2` means `encodeCutoutPNG` returned nil on
every device, every time, since it was written, so no earlier build could have
worked either. `LOCAL_BG_IOS_ENABLED` is `true` in the committed production
policy, so **this engine ships**. The release verifier is the only thing that has
been holding it back, and this IPA was produced with `PRE_DEVICE_VALIDATION=true`
to break the chicken-and-egg — the build has to exist before anyone can run it.

So **section 2 is the whole point of this pass.** Everything else is regression
cover.

Two more things to hold in mind:

* The app is **iPhone-only** (`TARGETED_DEVICE_FAMILY = 1`). On an iPad it runs
  in scaled compatibility mode and is not listed for iPad. Check it looks
  acceptable there; do not treat missing iPad layout as a bug.
* The AI-consent gate is verified on Android but **never on iOS**. It is the fix
  for the App Store rejection, so a failure here is a resubmission blocker.

Server flags are shared with Android and are currently **on**: `feature_discover`,
`feature_discover_stories`, `feature_shopping`.

---

## 1. Install and first launch

- [ ] TestFlight shows **1.0.21 (25)**; install it
- [ ] Cold launch does not crash
- [ ] Sign in (Google, Apple, or email) — note which you used
- [ ] Tab bar reads **HOME · DISCOVER · INBOX · PROFILE**, not "SOCIAL"
- [ ] Discover shows the story rail, "Which mood fits today?", **Picked for You**
      products, a **View Giveaway** card and a **Newsroom** read

> If tab 1 says SOCIAL, the flags call failed — tell me, do not keep testing
> Discover.

## 2. Apple Vision cutout — THE PRIORITY (A2 evidence)

Needs **iOS 17 or newer**. On iOS 15/16 the engine correctly reports unsupported
and falls back to the cloud; that is a valid result, but it does **not** produce
A2 evidence.

Do **five** separate Add Garment runs, and vary them:

- [ ] Orb → **Upload a Garment** → keep **Remove background** selected
- [ ] Run 1 — plain garment, clean background
- [ ] Run 2 — patterned garment on a **patterned** background (the hard case)
- [ ] Run 3 — something thin or wiry: glasses, a strap, a chain
- [ ] Run 4 — dark garment on a dark background
- [ ] Run 5 — anything; a repeat is fine

For each, record: **did a cutout appear**, was the edge clean, any background
bleed, roughly how long, and any crash. Then:

- [ ] Each result **saves to the closet** and renders with a transparent
      background in the grid
- [ ] **Fix cutout** is present; **Improve edges** is correctly absent
- [ ] No crash across all five

**Send me the five results and the iOS version + device model.** I record A2 with
`verify_local_cutout_release.py --record-device-evidence ios`, and only then does
`--target ios-production` pass. Do not hand-edit the fingerprint.

## 3. AI photo consent — the App Store fix

Use a **personal body photo**, not a studio model. The gate only fires for your
own photo, by design.

- [ ] Note your credit balance first: ______
- [ ] MoodMirror → body photo → 1 garment → **AI Couture** → Generate
- [ ] **The "AI Photo Processing" sheet appears BEFORE anything is sent.** It
      must name **FASHN.ai (FASHN LTD)** and **OpenAI**, say the safety check
      happens first, and link the Privacy Policy
- [ ] Tap **Not Now** → no render starts, **credits unchanged**, and your
      outfit / body / mode selections are all still there
- [ ] Generate again → **Allow & Continue** → it renders
- [ ] Generate a third time → **no sheet** (already granted)
- [ ] Settings → **Privacy & data** → AI Photo Processing shows **ALLOWED**
- [ ] **Review disclosure** reopens the same text
- [ ] **Withdraw permission** → status flips
- [ ] Next personal-photo render **asks again**
- [ ] Switch to a **studio model** → Generate → **no sheet ever** (it is our
      photo, not yours)
- [ ] **2D Try-On** → **no sheet ever** (runs entirely on device)

> A sheet that appears *after* the spinner starts is a failure. So is any credit
> being spent on Not Now.

## 4. AI Try-On

- [ ] AI Couture (1 credit) renders and the result appears
- [ ] Credits decrement by exactly 1, and **only on success**
- [ ] Force-quit mid-render, reopen → the job is not lost or double-charged
- [ ] A failed render **refunds** the credit
- [ ] Full Look is gated to Pro Max (4 credits) — check the gate, no need to buy

## 5. Purchases and subscriptions

`REVENUECAT_IOS_KEY` is set in Codemagic, so StoreKit should be live in
TestFlight (sandbox purchases, not real money).

- [ ] Paywall opens and shows real prices, not placeholders
- [ ] A sandbox purchase completes and the tier badge updates
- [ ] Settings → **Restore Purchases** works after a reinstall
- [ ] Settings → **Manage Subscription** opens the iOS subscription sheet

> If prices are blank or the paywall is empty, the RevenueCat iOS key or the ASC
> in-app-purchase config is wrong — tell me, that is a review blocker.

## 6. Newsroom

- [ ] Discover → the Newsroom read opens **inside the app**, not in Safari
- [ ] Back returns cleanly
- [ ] Only `https://` links open in the in-app browser

## 7. Giveaways — chat and delete

- [ ] Discover → **View Giveaway** opens the giveaway
- [ ] Create a giveaway, then open it as the owner → **Delete is visible**
- [ ] Delete it → it is **gone permanently**, for everyone, immediately
- [ ] Its claims and its pickup chat disappear too — **no orphan chat**
- [ ] Pickup chat: the typing area holds only what you type (no app-authored
      text stuck in the field), and the keyboard does not cover the send button

> Delete is a hard delete with a database cascade. If a deleted giveaway still
> appears anywhere, stop and tell me.

## 8. Saved Looks

- [ ] Save a look → it appears under Profile → **Looks**
- [ ] Delete a look → the placement is obvious and it disappears
- [ ] Saved products (the heart on Discover) persist across a relaunch

## 9. Notifications

- [ ] The permission prompt appears **contextually**, not on first launch
- [ ] Allow → a push arrives; tapping it deep-links to the right screen
- [ ] Deny → **Open settings** actually opens iOS Settings *(this is `cdee5af`,
      newly merged — it was a dead button on iOS before this build)*
- [ ] The small icon renders correctly in the notification

## 10. Account deletion — Apple requires this to work

Do this **last**, on a throwaway account if you can.

- [ ] Settings → **Export my data** produces the JSON
- [ ] Settings → **Delete Account** → confirm
- [ ] You are signed out and the account is gone
- [ ] Signing in again does **not** restore the old wardrobe

## 11. iPad — compatibility mode only

- [ ] Installs and launches on an iPad
- [ ] Scaled iPhone layout is usable — nothing clipped, no unreachable buttons
- [ ] Try-on and the consent sheet both work

---

## What to send back

1. **Section 2: all five cutout results**, plus iOS version and device model —
   this is what unblocks A2 and the App Store submission.
2. Anything in section 3 that did not behave exactly as written.
3. Any crash, with the TestFlight feedback screenshot.
4. Sections 5 and 10 outcomes — the two other things App Review will exercise
   directly.
