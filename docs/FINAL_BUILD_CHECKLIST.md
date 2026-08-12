# Final mobile build session — remaining checklist

All deployable server-side work is finished and live. What is left is the single
mobile build/test/release session.

**Written 2026-08-12 at `ee7b991`.** The blockers in section A were read from
`scripts/verify_local_cutout_release.py` at that commit, not from memory — re-run
it rather than trusting the numbers below if time has passed.

## Where things stand

| | |
|---|---|
| Production API | `wtm-api-prod` v39, `6ac1bbe` — consent enforcement **live** |
| Databases | migration `0066` applied to dev + prod |
| Legal site | published, `https://wearthemood.com/legal/privacy` |
| Admin console | working at `wearthemood.com/mood-ops-console-7x9` |
| App version | `1.0.20+24` in `app/pubspec.yaml` — needs a bump |

> **Live consequence while this session is pending.** Consent enforcement is on in
> production and no shipped client can grant it, so every installed build fails
> personal-photo try-on with `AI_DATA_SHARING_CONSENT_REQUIRED`. This was an
> accepted trade, not an oversight — the privacy boundary is deliberately
> fail-closed and must stay that way. 2D and studio-model try-on are unaffected.
> Section A is therefore on the critical path for restoring paid try-on.

---

## A. Hard blockers — the release verifier refuses the build

Everything else on both platforms passes. Re-check with:

```bash
python scripts/verify_local_cutout_release.py --target android-production
python scripts/verify_local_cutout_release.py --target ios-production
```

### A1. Android device evidence — 4 more passing runs

> `FAIL device evidence: only 1 passing android device run(s) across 1 session(s)
> at fingerprint ce512df42aa97fc6, 5 required`

Run Add Garment on a real device until there are 5 passing runs, then record:

```bash
python scripts/verify_local_cutout_release.py --record-device-evidence android \
  --recorded <YYYY-MM-DD> --app-version <version>
```

### A2. iOS device evidence — the whole matrix, never once run

> `FAIL device evidence: no recorded ios device run matches the current native
> code (fingerprint 2cb72faffd771f44)`

Apple Vision has **never** produced a cutout on physical hardware. The encoder
defect fixed in `bf945e2` means it could not have at any earlier point either —
`encodeCutoutPNG` returned nil on every device, every time, since it was written.
`LOCAL_BG_IOS_ENABLED` is `true` in the committed production policy, so this
engine *will* ship; the verifier is the only thing stopping it shipping unproven.
Needs a real iOS 17+ device.

> **Record evidence only after the code is final.** The fingerprint hashes the
> native sources plus `docs/bg/local_cutout_compatibility.json`, so any edit to
> the engine, the plugin, its registration, the pinned ML Kit client or the Vision
> revision invalidates prior evidence and forces the matrix to run again. Never
> hand-edit a fingerprint to make a build pass.

---

## B. Verify — do not assume

### B1. Google sign-in on a Play-delivered build

The **Play App Signing** SHA-1 is a different certificate from the upload key and
must be registered in the OAuth client. The trap is the delay: the first sign-in
uses an already-authorised cached credential and skips the API Console check
entirely. **"Sign-in worked once" does not prove the SHA-1 is registered.**

Test sign-in *after an explicit logout*, on a build delivered by Play — not a
local install. If it fails the fix is server-side only (add the SHA-1 to the
OAuth client); no rebuild, no version bump, no re-upload. See
`docs/ANDROID_SIGNING_KEYS.md`.

### B2. `assetlinks.json` needs the Play App Signing SHA-256

Referral deep links depend on it.

### B3. Lawyer review of the 13+ wording

Across privacy, acceptable-use and terms, before Play submission.

> The 13+ / 16+ figures are **not** drift. `PLAY_STORE_CHECKLIST.md` §5 reconciles
> three things that are allowed to differ: legal minimum eligibility **13+**
> (privacy + terms), Apple calculated content rating **13+**, and Play intended
> target audience **16–17 and 18+**. A legal minimum is not a target audience, and
> adding the 13–15 band would pull the app under Play Families policy. There is no
> in-app age gate, by founder decision.

---

## C. Code to land before building

- [ ] **Decide on `cdee5af`** (`fix/ios-notification-settings` — opens iOS Settings
      from a denied-permission CTA). The one completed commit not in the release
      branch. Client-only, so it is a free merge or a free skip.
- [ ] Finish the remaining client bugs.
- [ ] **Bump `version:`** in `app/pubspec.yaml` (currently `1.0.20+24`; Play prod
      is older).
- [ ] Re-run `dart format`, `flutter analyze`, `flutter test`.

---

## D. Build

- [ ] Android AAB **must** pass `--dart-define-from-file=env/prod.json` — without
      it Supabase never initialises.
- [ ] **R8 minify/shrink stays OFF.** It stripped WorkManager and caused a launch
      crash; the release verifier checks this.
- [ ] Never hand-edit `env/prod.json` — it is generated by
      `scripts/render_app_env.py` from the committed
      `app/env/feature_policy.prod.json`.
- [ ] iOS via Codemagic. **`submit_to_testflight: true` marks a good uploaded
      build FAILED** until Test Information is filled in — check
      `appStoreConnectTasks` separately from `buildActions`.
- [ ] Device-test the release build, not just debug.

---

## E. Device QA — highest risk first

### E1. The AI consent flow — never run on a device

Enforcement is already live in production, so this is the top risk in the session.

- [ ] Personal photo → AI mode → Generate → **sheet appears before any transmission**
- [ ] **Not Now** → no credits spent, no job created, outfit/mode/body preserved
- [ ] **Allow & Continue** → renders normally
- [ ] Second render → **no sheet**
- [ ] Settings → Privacy → AI Photo Processing → status, Review disclosure, Withdraw
- [ ] After withdrawing → next personal-photo render asks again
- [ ] 2D → never shows the sheet
- [ ] Studio model → never shows the personal-photo sheet

### E2. The client fixes riding along

- [ ] In-app news reader
- [ ] Giveaway / Looks delete placement
- [ ] Giveaway-chat typing area
- [ ] On-device engine warm-up before the first photo
- [ ] Notification small icon renders
- [ ] Closet paging, upload client reuse, chat poll delta

### E3. Standard passes

Credits · notifications · community · referral deep links · top-up and paywall.

---

## F. Store submission

**Play:** upload AAB · confirm target audience 16–17/18+ · re-check the Data
Safety form is still accurate after the consent change.

**App Store Connect** — every piece of text is already drafted in
`docs/APPLE_REVIEW_PRIVACY_RESPONSE.md`:

- [ ] §E → App Privacy answers. **Two need a decision:** *Usage Data → Product
      Interaction* (the PostHog key is empty in `env/prod.json`, so nothing is
      collected today — answer No unless a key is added) and *Health & Fitness*
      (optional height/weight).
- [ ] §C → App Review Information → Notes
- [ ] §D → Resolution Center reply
- [ ] Privacy Policy URL → `https://wearthemood.com/legal/privacy` (already live,
      with the verified provider terms)
- [ ] Ensure the review account can add a body photo, or step A1.3 of the
      reviewer script fails

---

## G. Not blocking

- Cloudflare **Origin Rule** for the ops console, to drop the Pages-Function proxy
  hop and keep the URL without a redirect. Needs a zone-scoped Cloudflare token;
  the credential in use is Pages-scoped and sees zero zones.
