# Digital Asset Links — Android App Links (`/r/<code>` referral invites)

`assetlinks.json` associates `wearthemood.com` (+ `www.`) with the Android app
`com.fashionos.app` so verified HTTPS App Links open the app directly when it is
installed. Served statically by Caddy at
`https://wearthemood.com/.well-known/assetlinks.json` (Content-Type
`application/json`, HTTPS, no redirect).

## ⚠️ One manual step: add the Google Play App Signing fingerprint

Google Play **re-signs** every install with the **App Signing key**, which is a
DIFFERENT certificate from the local **upload key**. App Links on Play-installed
builds verify against the **App Signing** SHA-256 — the upload-key fingerprint
already in this file only verifies **local release** installs (`adb install`).

Until the App Signing fingerprint is added, **deferred-install referral
attribution works fully** (it uses the Play Install Referrer, not App Links);
only *directly opening* an installed app from a `/r/<code>` link is **pending**.

To finish it:

1. Google Play Console → app **Wear The Mood** → **Test and release → Setup →
   App integrity → App signing**.
2. Copy the **"App signing key certificate" → SHA-256 certificate fingerprint**
   (colon-separated hex).
3. Add it as a second entry in `sha256_cert_fingerprints` here, e.g.:

   ```json
   "sha256_cert_fingerprints": [
     "27:CC:B9:D8:DC:95:3A:FB:78:69:27:30:05:EE:95:2F:77:73:BA:35:1F:E1:38:E2:C8:68:2F:14:22:BD:73:D0",
     "<PLAY_APP_SIGNING_SHA256_HERE>"
   ]
   ```

4. Redeploy the site and verify:
   - `curl -sS https://wearthemood.com/.well-known/assetlinks.json` returns the
     JSON with `Content-Type: application/json`, HTTP 200, no redirect.
   - On device: `adb shell pm verify-app-links --re-verify com.fashionos.app`
     then `adb shell pm get-app-links com.fashionos.app` shows `verified` for
     `wearthemood.com`.

Do not remove the upload-key fingerprint — keeping both lets local release builds
and Play builds both verify.

---

# Apple App Site Association — iOS Universal Links (`/r/<code>`)

`apple-app-site-association` (no extension) associates `wearthemood.com` with the
iOS app for Universal Links, so `https://wearthemood.com/r/<code>` opens the app
directly when installed. Served by Caddy over HTTPS with
`Content-Type: application/json` and **no redirect** (Apple requirements).

## ⚠️ One manual step: fill in the Apple Team ID

The file currently uses the placeholder `TEAMID`. Replace it with the real
**Apple Team ID** (10-char, e.g. `A1B2C3D4E5`) so `appIDs` reads
`"<TeamID>.com.fashionos.app"`. The Team ID is **not** in the repo (Codemagic
uses automatic signing).

1. Apple Developer → **Membership** → copy the **Team ID**; confirm the Bundle ID
   is `com.fashionos.app`.
2. Enable the **Associated Domains** capability on the App ID (already declared in
   `app/ios/Runner/Runner.entitlements` as `applinks:wearthemood.com`).
3. Edit `apple-app-site-association` → set `appIDs` to `["<TeamID>.com.fashionos.app"]`.
4. Redeploy the site and verify:
   - `curl -sSI https://wearthemood.com/.well-known/apple-app-site-association`
     → HTTP 200, `Content-Type: application/json`, no redirect.
   - On a device/TestFlight build, the diagnostics test at
     `https://app-site-association.cdn-apple.com/a/v1/wearthemood.com` resolves.

Until the real Team ID is set, iOS Universal Links stay **code-ready but not
verified** (the App-Store invite-code fallback still works fully). Deferred
attribution is NOT claimed on iOS — it uses the explicit invite code.

