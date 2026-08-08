# Android signing keys & Google sign-in — the permanent reference

Three different keys sign this app depending on how the build reached the device.
Each presents a **different certificate**, so each needs its SHA-1 registered in the
Android OAuth client or Google sign-in fails. None of them rotate — register all
three once and this never needs touching again.

Package: `com.fashionos.app` (never changes — set before first publish)
Android OAuth client: `939255107253-p5rlbraqh4gflovc7slk1lddpsj3ih58`
Google Cloud project: `939255107253`

## The three keys

| Key | SHA-1 | Signs | Stability |
|---|---|---|---|
| **Play App Signing** | `8E:1E:0C:7B:42:7E:81:F4:85:4A:B5:E0:6A:27:6B:B6:E3:2F:85:A3` | every build installed **from Google Play** | **permanent** — Google generated it once, re-signs every future release with it |
| Upload keystore (`UPLOAD` alias, `CN=Wear The Mood`) | `89:C6:D1:2E:A0:DA:CF:83:F5:C4:BF:ED:8C:01:9A:66:FE:FC:5E:72` | locally built release APK/AAB (what we sideload for testing) | stable while `app/android/key.properties` points at the same `.jks` |
| Debug keystore (`androiddebugkey`) | `7F:E9:37:21:EB:9D:B1:BE:EF:EF:F8:9B:62:D5:E0:E2:2C:DF:54:86` | `flutter run`, debug builds | stable per machine; differs on another machine or after an SDK reinstall |

Play App Signing SHA-256, for anything that wants it (Digital Asset Links,
`assetlinks.json` for App Links / referral deep links):

```
0F:EB:F2:B7:FD:6D:27:3D:A3:C0:BF:73:C9:EE:48:87:4F:26:E2:1F:93:9A:1B:5A:43:3C:45:08:76:9F:2C:EA
```

These fingerprints are **not secrets** — anyone can extract them from a published
APK. The keystore FILE and its passwords are the secrets, and those stay out of git.

## The failure this caused (2026-07-29, release 1.0.16+19)

Google sign-in succeeded on the first attempt after installing from Play, then
failed on every attempt after logging out:

```
W/Auth.Api.Credentials: [AccountReauth_flowRunner] Flow failed.
chbm: [8] Unknown error [status=UNREGISTERED_ON_API_CONSOLE]
```

Only the **upload key** SHA-1 was registered. The Play-delivered build is signed
with the **Play App Signing** key, which was not.

The delay is what makes this trap dangerous: the first sign-in used an
already-authorized cached credential and skipped the API Console check entirely.
Only after `ClearCredentialStateOperation` (logout) does Credential Manager run the
full re-auth flow, and that flow validates package + signing certificate against
the API Console. **So "sign-in worked once" does NOT prove the SHA-1 is registered.
Always test sign-in AFTER a logout.**

Fix was server-side only — add the SHA-1 to the OAuth client. No rebuild, no
version bump, no re-upload; it propagates in minutes.

## How to read a certificate yourself

Locally built AAB or an APK with a v1/JAR signature:

```bash
keytool -printcert -jarfile app/build/app/outputs/bundle/release/app-release-*.aab
```

Release APKs are v2-signed only, so `keytool` reads nothing — use apksigner:

```bash
"$ANDROID_SDK/build-tools/37.0.0/apksigner" verify --print-certs app-release.apk
```

The **Play** key can be read from a device that installed from Play — this is the
authoritative source and does not depend on Play Console:

```bash
adb shell pm path com.fashionos.app          # note the base.apk path
adb pull <that path>/base.apk
apksigner verify --print-certs base.apk      # DN will be CN=Android, O=Google Inc.
```

Play Console also shows it: **Test and release → Setup → App signing**.

Debug keystore:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -storepass android -keypass android
```

## When a SHA-1 genuinely does change

- You lose the upload keystore and Google issues a new upload key — the **Play App
  Signing key is unaffected**, so users never notice; only re-register the new
  upload SHA-1.
- New package name / new app entry in Play.
- Different dev machine or a wiped Android SDK — debug key only.
- CI-built debug artifacts are signed by the CI runner's own debug keystore, so
  they will not match the local debug SHA-1.

## Related

- Supabase needs the **client IDs** (comma-separated web/android/ios), not SHA-1s —
  a separate setting from this, and already configured.
- `serverClientId` for the native flow is the **web** client
  `939255107253-ds2dlmev0ihn2d6s75tbbvgfcala30bp`, supplied via
  `GOOGLE_WEB_CLIENT_ID` in `app/env/prod.json`.
