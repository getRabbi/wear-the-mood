# Fashion OS — Pre-launch Manual Test Checklist

Walk these in order on the device (build points at **https://api.wearthemood.com**).
Check each box as it passes. If one fails, note what you saw and tell Claude.

> **Known-stubbed — do NOT flag as bugs (yet):**
> - Push notifications (no Firebase service-account on the server yet)
> - Subscriptions / real purchase (RevenueCat not wired) — paywall *screen* shows
> - Garment auto-tagging (Claude vision is out of credits → tags may be empty)
> - "Shop" links go to a plain web search (no affiliate program yet)

---

## 1. Auth (§23)
- [ ] **Sign Up** tab is clearly different from Sign In (segmented toggle at top)
- [ ] Sign up with email + password + **Confirm password** (mismatch shows an error)
- [ ] Sign out, then **Sign in** with the same email/password
- [ ] **Continue with Google** → browser → pick account → returns into the app, signed in
- [ ] (Optional) Email already registered → friendly error, not a crash

## 2. Consent + Avatar (§10, the "aha")
- [ ] First face/body capture is **blocked until you accept consent**
- [ ] Create avatar (selfie + body data) → saves, no error
- [ ] Re-open the app → still signed in, avatar persists

## 3. Try-on — the hook (§7, §17)
- [ ] Try-on picker shows **your wardrobe items** (not random sample images)
- [ ] If wardrobe empty → "Your wardrobe is empty" + **Add clothes** button
- [ ] Pick a garment → **Try it on** button enables
- [ ] Tap Try on → progress (queued → processing) → **result reveal**
- [ ] **Credits drop by 1 on success only** (check the credits chip before/after)
- [ ] Spend until 0 → next try-on → **out-of-credits → paywall**, no charge

## 4. Wardrobe — the data moat (§1 pillar 2)
- [ ] Add an item (camera/upload) → **"Removing background"** overlay appears
- [ ] Tile **updates to the cutout by itself** within a few seconds (no manual refresh)
- [ ] Grid shows items; pull-to-refresh works
- [ ] **Search** the closet (type a description) → relevant items come back
- [ ] Long-press a tile → **Mark as worn** (wear count/insights update)
- [ ] Long-press → **Remove** → item disappears
- [ ] **Outfits** (top-right) → build + save an outfit
- [ ] **Insights** (top-right) → cost-per-wear / ROI numbers render
- [ ] **Closet gaps** → suggested missing essentials

## 5. Stylist — the habit (§1 pillar 3)
- [ ] "What do I wear today?" → a **real suggestion** appears (powered by OpenAI)
- [ ] Suggestion references your wardrobe / weather context

## 6. Social — community (§1 pillar 4, §19)
- [ ] Create an **OOTD post** → appears in the feed
- [ ] **Like** a post; **comment** on a post
- [ ] **Follow** flow works
- [ ] Post menu → **Report**; **Block** a user
- [ ] Try posting obviously bad text → moderation handles it (keyword fallback)

## 7. News & commerce (§1 pillar 5)
- [ ] **News feed** shows ~30 real articles with summaries
- [ ] Open an article → **trend-to-closet** ("shop this from your closet")
- [ ] **Shop the look** → opens a product/web search link

## 8. Profile + account lifecycle (§10 — mandatory for the store)
- [ ] Profile screen loads (name, avatar)
- [ ] Legal links open: **Privacy / Terms / Acceptable Use** (wearthemood.com/legal/*)
- [ ] **Export my data** → returns your data
- [ ] **Delete account** → account + data removed, app returns to signed-out

## 9. Cross-cutting / polish
- [ ] Every screen has a proper loading + empty + error state (no bare spinners)
- [ ] Dark mode looks right
- [ ] No raw error codes shown to the user (friendly messages)
- [ ] Back navigation + deep behavior feels right

---

When all of §1–§8 pass, the app is ready for the **signed AAB + Play closed test**.
