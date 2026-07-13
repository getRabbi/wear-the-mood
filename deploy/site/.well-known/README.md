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
