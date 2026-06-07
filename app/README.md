# Fashion OS — Flutter app

Mobile client (Android-first). Part of the Fashion OS monorepo — see the
[root README](../README.md) and [`CLAUDE.md`](../CLAUDE.md) (source of truth).

## Run

```bash
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

Environment config: [`env/README.md`](env/README.md). **The app holds no secrets.**

## Code generation (freezed / json_serializable / riverpod_generator)

```bash
dart run build_runner build --delete-conflicting-outputs
# while iterating:
dart run build_runner watch --delete-conflicting-outputs
```

## Structure (`lib/`)

| Folder | Purpose |
|---|---|
| `core/`     | env, theme, router, network, analytics |
| `data/`     | models, repositories, sources (Supabase + API clients) |
| `features/` | onboarding · auth · profile · tryon · wardrobe · stylist · social · news · paywall |
| `shared/`   | reusable widgets + utils |
| `l10n/`     | localized strings (English now; i18n-ready) |
