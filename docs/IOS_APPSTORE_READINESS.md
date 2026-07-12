# iOS / App Store readiness — Wear The Mood

> Status as of 2026-07-12. Code work is DONE and validated (`flutter analyze` clean,
> 516/516 tests green). What remains is owner/dashboard work — every item is listed
> below with exactly where it goes. **Nothing was pushed; no iOS archive has been
> attempted yet** (that happens on Codemagic once credentials are configured).

---

## 1. Code changes completed

| Area | What changed |
|---|---|
| iOS project | `Info.plist`: display name **Wear The Mood**, camera/photo/photo-add permission strings, `com.fashionos.app` URL scheme (Supabase OAuth/password-reset callback), `ITSAppUsesNonExemptEncryption=false`, `UIBackgroundModes=remote-notification`. |
| Xcode project | Deployment target **13.0 → 15.5** (ML Kit pose detection requires 15.5), `TARGETED_DEVICE_FAMILY = 1` (iPhone-only launch), `CODE_SIGN_ENTITLEMENTS` wired, `GoogleService-Info.plist` + `PrivacyInfo.xcprivacy` added to the Runner target/Resources. Bundle ids were already correct (`com.fashionos.app` / `.RunnerTests`). |
| Podfile | Created (was missing): `platform :ios, '15.5'`, ML Kit arch exclusion, per-pod 15.5 floor. |
| Entitlements | `ios/Runner/Runner.entitlements` (new): `aps-environment=production`, Sign in with Apple. |
| Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy` (new): app's own code — no tracking, no tracking domains, no required-reason APIs, no app-level collected-data entries (SDK pods carry their own manifests; disclosures go in the ASC questionnaire). |
| Launch screen | Background set to the WTM scaffold color `#08060F` (no white flash; no Flutter branding — the LaunchImage slots stay blank). |
| App icons | iOS icon set generated from the founder's existing `assets/icon/app_icon.png` via `flutter_launcher_icons` (`ios: true`, `remove_alpha_ios: true`). The 1024×1024 marketing icon is RGB **without alpha** (verified). Android icons unchanged (byte-identical output). |
| Sign in with Apple | Implemented end-to-end on the existing Supabase architecture: `sign_in_with_apple` 7.0.1 + secure nonce (`core/auth/apple_nonce.dart`) → `auth.signInWithIdToken(OAuthProvider.apple)`. First-login name persisted only when Apple returns it; cancel ≠ error; same profile system (Supabase links same-verified-email accounts; Hide My Email creates its own account by design). The existing WTM auth screen button (iOS-only) now works. |
| Google Sign-In iOS | No Dart change needed (native `serverClientId` flow + browser fallback already work). The iOS `REVERSED_CLIENT_ID` URL scheme is injected **at CI time** from the real `GoogleService-Info.plist` — no fake value in the repo. |
| Firebase / push | `getToken()` guarded behind APNs-token readiness on iOS; token registration now sends the real `platform` ('ios'/'android'); best-effort token **unlink on sign-out**; push `route` payloads validated (`isValidPushRoute`) before routing. |
| RevenueCat | Platform key split: `REVENUECAT_IOS_KEY` added (env-driven; `features/paywall/store_config.dart` selects per platform — the Android key is never used on iOS). Package ids centralized (`StorePackages`). Manage-subscription URL is platform-aware (App Store vs Play). |
| Settings | New rows: **Restore Purchases**, **Manage Subscription**, **Community Guidelines** (hosted acceptable-use page), Help & Support now emails the listed support address. Existing delete-account flow untouched (already compliant: in-app, double-confirmed, server-side `/v1/account`, sign-out). |
| Reports | Reason list extended to the store-review set (spam, harassment, nudity/sexual, violence, hate speech, scam/misleading, IP violation, other). Server contract unchanged (reason is a string). |
| Giveaways | iOS-only "Apple is not a sponsor of or involved in this giveaway." appended to the disclaimer shown at create + detail/claim. |
| Permissions UX | Denied/restricted camera/photo access now shows a helpful dialog with **Open Settings** (iOS `app-settings:`) at all five WTM pick entry points (closet add, compose, profile photo, body photo, giveaway create) instead of a generic failure snack. HEIC/HEIF/orientation already handled (picker transcodes; compression strips EXIF and bakes orientation). |
| Codemagic | New `ios-release` workflow (tag `ios-v*`): analyze + test → real `GoogleService-Info.plist` from a secure var (fails clearly if missing; refuses the CI placeholder) → REVERSED_CLIENT_ID scheme injection → automatic App Store signing → `flutter build ipa` (TestFlight-continuing build number when `APP_STORE_APP_ID` is set) → **TestFlight upload only, never auto-submit to review**. `ios-compile-check` gained a clearly-labeled CI-only placeholder plist so it still runs without secrets. `android`/`android-release` workflows unchanged (prod-env writer factored into a shared anchor, now also carrying the inert-on-Android iOS key). |
| Tests | +14 new tests: RevenueCat key selection per platform (incl. "no silent Android-key fallback on iOS"), manage-URL selection, Apple nonce charset/uniqueness/SHA-256 vector, Apple sign-in success/cancel/failure states, push-route validation, permission-denial detection. 1 existing test updated (report sheet grew, block row needs a scroll). |

### Files changed

- `app/ios/Runner/Info.plist`, `app/ios/Runner.xcodeproj/project.pbxproj`, `app/ios/Podfile` (new), `app/ios/Runner/Runner.entitlements` (new), `app/ios/Runner/PrivacyInfo.xcprivacy` (new), `app/ios/Runner/Base.lproj/LaunchScreen.storyboard`, `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*`
- `app/lib/core/auth/apple_nonce.dart` (new), `app/lib/core/media/image_pick_permission.dart` (new), `app/lib/features/paywall/store_config.dart` (new)
- `app/lib/core/env/app_env.dart`, `app/lib/core/push/push_messaging.dart`, `app/lib/core/legal/legal_links.dart`, `app/lib/data/repositories/auth_repository.dart`, `app/lib/features/auth/auth_controller.dart`, `app/lib/features/paywall/{revenue_cat_client,subscription_service}.dart`, `app/lib/features/giveaway/{giveaway_disclaimer,create_giveaway_screen}.dart`, `app/lib/ui/auth/wtm_auth_screen.dart`, `app/lib/ui/paywall/wtm_paywall_screen.dart`, `app/lib/ui/profile/{wtm_settings_screen,wtm_profile_photo}.dart`, `app/lib/ui/closet/wtm_add_garment_screen.dart`, `app/lib/ui/community/{wtm_compose_screen,wtm_community_shared}.dart`, `app/lib/ui/mirror/wtm_body_photo_screen.dart`
- `app/lib/l10n/app_en.arb` + regenerated `app_localizations*.dart`
- `app/pubspec.yaml` (+ `sign_in_with_apple` 7.0.1 MIT, `crypto` 3.0.7 BSD-3 promoted, iOS icon generation), `app/pubspec.lock`, `LICENSES.md`
- `app/env/{dev,prod}.json.example`, `app/env/README.md` (`REVENUECAT_IOS_KEY`)
- `codemagic.yaml`
- `app/test/…` (5 new files, 1 updated)

## 2. Bundle ID & version configuration

- Main app: `com.fashionos.app` (Debug/Profile/Release) — unchanged, matches Android.
- Tests: `com.fashionos.app.RunnerTests` — unchanged.
- Version stays Flutter-managed: `CFBundleShortVersionString = $(FLUTTER_BUILD_NAME)`, `CFBundleVersion = $(FLUTTER_BUILD_NUMBER)` from `pubspec.yaml` (`1.0.6+7`). The ios-release workflow can auto-continue the TestFlight build number (see §4).
- Deployment target: **iOS 15.5** (forced by ML Kit pose detection). Device family: iPhone only (rollback: set `TARGETED_DEVICE_FAMILY = "1,2"` back in project.pbxproj — but then iPad screenshots + iPad-quality UI become review requirements).

## 3. Owner-provided items still required (the complete shopping list)

1. **Apple Developer Program membership** ($99/yr) for a Team ID.
2. **Real `GoogleService-Info.plist`** for iOS app `com.fashionos.app` (Firebase console) — as base64 into Codemagic (`GOOGLE_SERVICE_INFO_PLIST_B64`). Never commit it (already git-ignored).
3. **APNs Auth Key (.p8)** uploaded to Firebase (not to the repo, not to Codemagic).
4. **App Store Connect API key (.p8)** added as a Codemagic integration named exactly `wtm_app_store_connect`.
5. **RevenueCat iOS public SDK key** (`appl_…`) → `REVENUECAT_IOS_KEY` in the `app_prod_config` group (and in the git-ignored local `app/env/prod.json` — the example file already has the field).
6. **Apple product IDs** created in App Store Connect and attached in RevenueCat (suggested, final call is the owner's): `wtm_pro_monthly`, `wtm_pro_max_monthly` (+ yearly variants when wanted). No consumable top-up exists in the app today — credits come from the daily quota + membership pool, so no consumable product is needed at launch.
7. **Legal pages live** at wearthemood.com/legal/{privacy,terms,acceptable-use} (files exist in `legal/`; deploy = existing site flow).
8. **Review demo account** (email+password on prod) for App Review, with some closet/looks content.
9. Optional: `APP_STORE_APP_ID` (numeric Apple app id) in `ios_config` for TestFlight build-number auto-increment.

## 4. Codemagic setup (dashboard)

- Integration: **App Store Connect API key** named `wtm_app_store_connect` (Team settings → Integrations). The `ios_signing` block then fetches/creates the App Store distribution cert + profile automatically.
- Env group `app_prod_config` (already used by android-release): add `REVENUECAT_IOS_KEY`.
- New env group `ios_config`: `GOOGLE_SERVICE_INFO_PLIST_B64` (secure), optional `APP_STORE_APP_ID`.
- Trigger: push tag `ios-v*` (e.g. `ios-v1.0.6`). Artifacts: IPA + dSYMs. Publishing: TestFlight only.
- The workflow **fails with a clear message** when a required secret is missing; it never falls back to fakes.

## 5. Apple Developer portal (developer.apple.com)

1. Create/confirm App ID `com.fashionos.app` with capabilities: **Push Notifications**, **Sign In with Apple**.
2. Create an **APNs key** (Keys → +, Apple Push Notifications service) → download `.p8`, note Key ID + Team ID.
3. No manual certificates/profiles needed — Codemagic's automatic signing handles them via the ASC API key.

## 6. App Store Connect

1. Create the app: name **Wear The Mood**, bundle `com.fashionos.app`, iPhone.
2. Create subscriptions (one group, e.g. "Atelier Membership"): Pro monthly + Pro Max monthly (+ yearly later). Fill Apple's required subscription metadata + review screenshot.
3. **App Privacy questionnaire** — declare honestly: photos/videos (user content, app functionality), email + user id (account), purchase history (RevenueCat), crash/diagnostics (Sentry), product interaction (PostHog), NO tracking across apps.
4. Age rating: expect **17+/18+** (user-generated content + AI imagery) — matches the Android positioning.
5. App Review notes: demo account, explain the AI try-on (input moderation + failed-generation refunds), giveaway = free P2P with in-app rules + Apple disclosure.
6. Links: Privacy Policy URL, Terms (EULA) URL, support URL/email (uprightseo24@gmail.com).

## 7. Firebase console

1. Add an **iOS app** (`com.fashionos.app`) to project `fashionos-499119` → download `GoogleService-Info.plist` → base64 into Codemagic (see §4). (`base64 -w0 GoogleService-Info.plist` on Linux, `base64 -i … | tr -d '\n'` on macOS, or `[Convert]::ToBase64String([IO.File]::ReadAllBytes('GoogleService-Info.plist'))` in PowerShell.)
2. Upload the **APNs .p8 key** (Project settings → Cloud Messaging → Apple app configuration) with Key ID + Team ID. FCM to iOS does not work without this.
3. The iOS plist also carries the iOS `CLIENT_ID`/`REVERSED_CLIENT_ID` used by native Google sign-in — make sure the Google sign-in provider is enabled for the iOS OAuth client in the Google Cloud console (same project), and keep `GOOGLE_WEB_CLIENT_ID` (already in prod config) as the `serverClientId`.

## 8. RevenueCat dashboard

1. Add an **App Store app** to the existing Wear The Mood project (bundle `com.fashionos.app`); paste the App Store Connect **In-App Purchase key / app-specific shared secret** per RevenueCat's flow.
2. Copy its **public SDK key** (`appl_…`) → `REVENUECAT_IOS_KEY` (Codemagic group + local prod.json).
3. Attach the new Apple products to the **existing offering packages** `pro_monthly` and `pro_max_monthly` (same entitlement `premium`) — the app reads packages, so no code change.
4. Keep the existing server webhook; entitlements stay server-verified cross-platform.
5. The `rc-a80b1eb705` deep-link scheme was **deliberately not added** — the app doesn't use RevenueCat web purchases/paywall previews. Add it to `CFBundleURLTypes` only if that feature is adopted.

## 9. Supabase / backend

1. **Enable the Apple provider** (Authentication → Providers → Apple): Client IDs = `com.fashionos.app` (the native flow needs only the bundle id; add a Services ID + secret only if web-based Apple auth is wanted later).
2. Confirm `com.fashionos.app://login-callback/` stays in the Redirect URLs allowlist (it's shared with Android).
3. No new migrations are required for iOS.
4. Follow-up (post-launch, before the first Apple-account deletion request spike): Apple **token revocation** on account deletion (`/v1/account`) — Apple requires apps that offer Sign in with Apple to revoke tokens when the account is deleted. That's a backend change (Apple `revoke` endpoint with a Services key); the current deletion flow (auth user + data wipe) already removes the Supabase identity. Tracked here, not silently skipped.

## 10. TestFlight checklist (first device pass)

- [ ] Cold start → WTM splash → auth gate (dark launch frame, no white flash)
- [ ] Email sign-in/up + password reset deep link (`com.fashionos.app://login-callback`)
- [ ] Google sign-in (native picker; browser fallback returns into the app)
- [ ] **Sign in with Apple**: fresh account, cancel (no error flash), Hide My Email, second login (no name overwrite), sign out/in again
- [ ] Notification permission prompt from the Notifications screen (not at launch); push arrives; tapping routes correctly (cold + background)
- [ ] Camera + photo library picks on every entry point; deny camera in Settings → helpful dialog with Open Settings
- [ ] HEIC portrait photo from the iPhone camera roll uploads with correct orientation
- [ ] AI try-on end-to-end: progress → result; airplane-mode failure → friendly error, credit not lost; backgrounding during generation resumes cleanly
- [ ] Paywall: Apple-localized prices show, purchase sandbox flow, cancel purchase (no error), **Restore Purchases** (paywall + Settings), Manage Subscription opens the App Store sheet, already-subscribed state
- [ ] Community: report each content type (9 reasons), block hides content, giveaway shows the Apple disclosure on iOS
- [ ] Settings: data export, **Delete Account** end-to-end → lands on sign-in
- [ ] Safe areas: Dynamic Island overlap, home-indicator clearance, keyboard over compose/auth fields, sheet scrolling (report sheet reaches Block)

## 11. App Store review checklist

- [ ] Guideline 4.8: Sign in with Apple present alongside Google ✅ (code done)
- [ ] 3.1.1: purchases via IAP only; no external checkout links in-app ✅ (Lemon Squeezy/Paddle plans stay OUT of the iOS app)
- [ ] 3.1.2: paywall shows price, period, auto-renew disclosure, Restore, Privacy + Terms ✅
- [ ] 5.1.1(v): in-app account deletion ✅
- [ ] 1.2 UGC: report + block + guidelines link ✅; moderation is server-side
- [ ] 5.3.4: giveaway Apple disclosure ✅
- [ ] 2.1: demo account + review notes (owner)
- [ ] 5.1.1: permission strings match actual use ✅; App Privacy answers match reality (owner)
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption=false` ✅

## 12. Remaining blockers (nothing code-side)

| Blocker | Needed for | Where |
|---|---|---|
| Apple Developer membership + Team ID | signing anything | §5 |
| ASC API key in Codemagic (`wtm_app_store_connect`) | ios-release workflow | §4 |
| Real GoogleService-Info.plist (b64 secure var) | Firebase/FCM/Google sign-in on iOS; ios-release fails fast without it | §7 |
| APNs key in Firebase | push delivery | §7 |
| RevenueCat iOS app + `REVENUECAT_IOS_KEY` + Apple products | purchases on iOS (until then paywall is informational — safe) | §8 |
| Supabase Apple provider ON | Sign in with Apple actually authenticating | §9 |
| Legal pages deployed | store listing + in-app links | §3.7 |
| A Mac is NOT needed — Codemagic covers build/sign/upload; the iPhone is needed for TestFlight testing. | | |

## 13. Rollback notes

- **Deployment target 15.5 / iPhone-only / entitlements / plist entries**: all in 3 files (`project.pbxproj`, `Info.plist`, `Runner.entitlements`) — revert the single scaffolding commit to restore the stock template. Android is untouched by these.
- **GoogleService-Info.plist Xcode reference**: local iOS builds now require the file to exist. On a Mac without it: copy the CI placeholder trick from `codemagic.yaml` (`ios-compile-check` step) — never ship that placeholder.
- **Apple sign-in**: UI-gated to iOS; Android behavior identical. Removing the `sign_in_with_apple` dependency + the `signInWithApple` methods restores the old "coming soon" state (also restore the `wtmAuthAppleSoon` arb string).
- **RevenueCat key split**: `store_config.dart` is the single seam — Android continues to read `REVENUECAT_ANDROID_KEY` exactly as before; reverting only removes iOS support.
- **Report-sheet reasons / settings rows / giveaway line**: pure additive UI; each is one small hunk.
- **Codemagic**: android workflows changed only by the shared `*write_prod_env` anchor (same script text + one extra inert key). The previous inline copy can be restored from git history.
