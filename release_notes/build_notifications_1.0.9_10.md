# Build record — Notifications refinement (1.0.9+10)

Internal build + QA record (not Play Store "what's new" copy). Covers the
7-category push preferences + FCM invalid-token pruning work.

## Artifact
- **File:** `app/build/app/outputs/bundle/release/app-release.aab` (not renamed)
- **Size:** 108.4 MB (113,698,651 bytes)
- **Version:** 1.0.9+10 (versionName `1.0.9`, versionCode `10`)
- **Package:** `com.fashionos.app`
- **AAB SHA-256:** `6c52498240626ba9d7ea5fe69934ec48e559ff76a70038f8efdb26b87b773079`
- **Signature:** `jar verified` — upload key `CN=Wear The Mood, OU=Mobile, O=Wear The Mood, L=Dhaka, ST=Dhaka, C=BD`
  - **Signer cert SHA-256:** `27:CC:B9:D8:DC:95:3A:FB:78:69:27:30:05:EE:95:2F:77:73:BA:35:1F:E1:38:E2:C8:68:2F:14:22:BD:73:D0`

## Change summary
- Branch `feat/cross-platform-referrals-notifications` — commits `e1def02` (backend), `6dd3583` (app). Not merged.
- Backend: 7 canonical push categories (migration `0043`), FCM `DeliveryStatus` + invalid-token pruning (`device_tokens.invalidated_at`, never deleted), master + per-category delivery gate. Deployed to prod (api + worker); sender = fcm, health 200, 0 secret leaks, 0 mass-send.
- App: 7-category prefs screen + OS-permission master status (Enable / Open settings). `flutter analyze` clean; 582 backend tests green.

## Manual on-device push verification (owner step — not doable from CLI)
No device is attachable here; verify on a real device signed into a test account:

- [ ] Install this AAB (or a matching debug build), open **Settings → Notifications**, allow the OS prompt → master row shows *Push notifications are on*.
- [ ] Trigger a `referral_reward` (or have someone like/follow the account) → push arrives on the **wtm_account / wtm_social** channel; tapping it deep-links (`/wtm/referral` or the inbox).
- [ ] Toggle a category **off** → trigger that event → **no push**, but the item still appears in the in-app notification center. Toggle back on → push resumes.
- [ ] Block notifications in system settings → master row shows *blocked* + **Open settings** action; category toggles remain editable.
- [ ] (Pruning) Uninstall/reinstall to force a new FCM token → the old token is auto-deactivated on the next send (no code action needed).
