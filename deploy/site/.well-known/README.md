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

`apple-app-site-association` (no extension) associates `wearthemood.com` **and
`www.wearthemood.com`** with the iOS app for Universal Links, so
`https://wearthemood.com/r/<code>` opens the app directly when installed. Served
by Caddy over HTTPS with `Content-Type: application/json` and **no redirect**
(Apple requirements).

## Configured appID (Apple Team ID set)

- **Apple Team ID:** `Z3YJ7Z29HT`
- **Bundle ID:** `com.wearthemood.app`
- **AASA `appIDs`:** `["Z3YJ7Z29HT.com.wearthemood.app"]`
- **Associated Domains** (`app/ios/Runner/Runner.entitlements`):
  `applinks:wearthemood.com` + `applinks:www.wearthemood.com`. Apple fetches the
  AASA from each domain's `/.well-known/`; Caddy (`deploy/Caddyfile`) serves the
  same file at both hosts, and the app's own link parser
  (`app/lib/core/referral/app_link_channel.dart`) accepts both hosts.

The Apple Team ID is a **public** identifier — it ships inside this publicly
served AASA file — so keeping it in the repo is expected (nothing secret here).

### Post-deploy verification

Redeploy the site (`deploy/site/` → droplet), then:

1. `curl -sSI https://wearthemood.com/.well-known/apple-app-site-association`
   → HTTP 200, `Content-Type: application/json`, no redirect. Repeat for
   `https://www.wearthemood.com/.well-known/apple-app-site-association`.
2. On a device/TestFlight build, Apple's diagnostics at
   `https://app-site-association.cdn-apple.com/a/v1/wearthemood.com` resolves.

Until the site is redeployed with this file, iOS Universal Links stay
**code-ready but not live** (the App-Store invite-code fallback still works
fully). Deferred attribution is NOT claimed on iOS — it uses the explicit
invite code.

