/// Compile-time environment configuration, injected via
/// `--dart-define-from-file=env/<env>.json` (see `app/env/README.md`).
///
/// Holds ONLY client-safe public values (CLAUDE.md §11). Secret keys
/// (service-role, Anthropic, OpenAI, FASHN, …) live in the backend, never here.
library;

enum AppEnvironment { dev, staging, prod }

/// Typed accessors over the `--dart-define` values. All values are resolved at
/// compile time, so these are `const`.
abstract final class AppEnv {
  static const String _environmentName = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'dev',
  );

  static AppEnvironment get environment => switch (_environmentName) {
    'prod' => AppEnvironment.prod,
    'staging' => AppEnvironment.staging,
    _ => AppEnvironment.dev,
  };

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Google OAuth **Web** client id, used as `serverClientId` for native Google
  /// sign-in so we get an `idToken` to hand to Supabase. Empty until the founder
  /// configures the Android OAuth client — the app then falls back to the
  /// system-browser OAuth flow (CLAUDE.md §23).
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');

  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );

  static bool get isDev => environment == AppEnvironment.dev;
  static bool get isProd => environment == AppEnvironment.prod;

  /// Required public config for talking to Supabase. Used by `bootstrap` to
  /// fail fast in dev when the env file hasn't been filled in.
  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
