# Release build — Wear The Mood (`com.fashionos.app`)

How to build the **signed Android App Bundle (`.aab`)** for Play Store upload.
Play needs an **`.aab`** (not an APK) and it must be **release-signed** (a
debug-signed build is rejected).

> Last verified build: `main` @ `eece0d7`, version `1.0.0+1`, signed with the
> upload key `CN=Wear The Mood` (SHA-256 `27:CC:B9:D8:…:73:D0`).

---

## 0. One-time setup (already done — for reference / a new machine)

**Upload keystore** (generate ONCE; reuse for every release — never regenerate):
```
keytool -genkeypair -keystore <path>/wearthemood-upload-keystore.jks \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```
**`app/android/key.properties`** (git-ignored — holds the passwords):
```
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=<absolute path to wearthemood-upload-keystore.jks>
```
`app/android/build.gradle.kts` reads this for release signing; if it's absent the
release build falls back to debug-signing (NOT uploadable).

### 🔒 Keep these safe (lose them → can't update the app)
- Keystore: `C:\Users\User\wearthemood-upload-keystore.jks`
- Passwords: `app/android/key.properties`
- Back both up (Drive / password manager). **Never commit them** — `*.jks` +
  `key.properties` are git-ignored. Upload-key SHA-256 is registered with Play.

---

## 1. Bump the version (every release after the first)
Edit `app/pubspec.yaml` line `version: X.Y.Z+N`:
- `+N` (versionCode) **must increase every upload** or Play rejects it as a duplicate.
- e.g. `1.0.0+1` → next release `1.0.1+2` (or `1.0.0+2` for the same version name).

## 2. Build the signed AAB
```
cd E:/dopplefit/app
flutter build appbundle --release --dart-define-from-file=env/prod.json
```
- `appbundle` (not `apk`) → Play format.
- `--dart-define-from-file=env/prod.json` → points the app at the **live prod
  backend** (`api.wearthemood.com` + prod Supabase). Without it the app targets
  the dev/emulator default and won't work for testers.

**Output:** `app/build/app/outputs/bundle/release/app-release.aab`

## 3. Verify it's signed with the upload key (not debug)
```
"E:/Android/jbr/bin/keytool.exe" -printcert -jarfile \
  app/build/app/outputs/bundle/release/app-release.aab
```
Expect `Owner: CN=Wear The Mood …` (NOT "Android Debug") and a validity well past
2033.

## 4. Upload to Play Console
1. **Internal testing** → Create release → upload `app-release.aab`.
2. First upload: accept **Play App Signing** (Google holds the app-signing key;
   you keep the upload key).
3. Fill listing / Data Safety / content rating (see `STORE_LISTING.md`,
   `PLAY_STORE_SCREENSHOTS.md`, `PLAY_STORE_CHECKLIST.md`).
4. **Closed test ~12–20 testers / ~14 days** (required for new personal accounts)
   → then Production.

---

## Notes
- **Cost:** local build is free; no Mac needed for Android. Codemagic is optional
  (the `android-release` workflow builds the same AAB on a `v*` tag, free tier) —
  see `codemagic.yaml`.
- **targetSdk 36 / minSdk 24** — already meets Google's API-35 minimum.
- No `READ_MEDIA_IMAGES` (uses the Android Photo Picker) → no Play "Photo & Video
  Permissions" declaration needed.
- Don't `flutter clean` between bumping the version and building unless needed; if
  you do, re-run `flutter pub get` first.
