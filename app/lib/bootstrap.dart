import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/secure_local_storage.dart';
import 'core/env/app_env.dart';

/// Central app initialization. `main.dart` stays a thin entrypoint so all
/// SDK/platform setup lives in one place. Every integration is gated on its
/// env config, so the app runs locally without any keys.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppEnv.hasSupabaseConfig) {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      // The app holds only the public (anon/publishable) key (CLAUDE.md §11).
      publishableKey: AppEnv.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: SecureLocalStorage(),
      ),
    );
  }

  if (AppEnv.posthogApiKey.isNotEmpty) {
    final config = PostHogConfig(AppEnv.posthogApiKey)
      ..host = AppEnv.posthogHost;
    await Posthog().setup(config);
  }

  final sentryDsn = AppEnv.sentryDsn;
  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = sentryDsn;
      options.environment = AppEnv.environment.name;
      options.sendDefaultPii = false; // privacy (CLAUDE.md §10)
      options.tracesSampleRate = 0.1;
    }, appRunner: _runApp);
  } else {
    _runApp();
  }
}

void _runApp() {
  runApp(const ProviderScope(child: FashionOsApp()));
}
