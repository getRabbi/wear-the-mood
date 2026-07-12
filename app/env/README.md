# App environment config (`app/env/`)

The Flutter app holds **no secret keys** — all AI / 3rd-party keys are backend-only
(CLAUDE.md §11). Only **client-safe public values** belong here:

- `ENVIRONMENT` — `dev` | `staging` | `prod`
- `API_BASE_URL` — the FastAPI backend base URL
- `SUPABASE_URL` + `SUPABASE_ANON_KEY` — the *anon* (public) key only, never the service-role key
- `SENTRY_DSN`, `POSTHOG_API_KEY`, `POSTHOG_HOST` — public client telemetry keys
- `REVENUECAT_ANDROID_KEY` / `REVENUECAT_IOS_KEY` — RevenueCat **public** SDK keys,
  one per platform from the same RevenueCat project (never the secret key; the
  Android key must never be used on iOS or vice versa)

## Usage

1. Copy the template for your environment (drop the `.example` suffix):
   ```
   copy env\dev.json.example env\dev.json        # Windows
   cp    env/dev.json.example env/dev.json        # macOS/Linux
   ```
2. Fill in real values. `dev.json`, `staging.json`, `prod.json` are **git-ignored**.
3. Run with the chosen environment:
   ```
   flutter run   --dart-define-from-file=env/dev.json
   flutter build apk --dart-define-from-file=env/prod.json --release
   ```

## Notes

- `API_BASE_URL` default `http://10.0.2.2:8000` is the Android **emulator's** alias for
  your host machine's `localhost`. On a real device, use your machine's LAN IP
  (e.g. `http://192.168.x.x:8000`).
- The typed Dart loader that reads these via `String.fromEnvironment` is added with the
  Flutter skeleton (Step 3). Until then these files just define the contract.
