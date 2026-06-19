import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/secure_local_storage.dart';
import 'core/env/app_env.dart';
import 'core/push/push_messaging.dart';

/// Central app initialization. `main.dart` stays a thin entrypoint so all
/// SDK/platform setup lives in one place. Every integration is gated on its
/// env config, so the app runs locally without any keys.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase / FCM push (§20). Android reads android/app/google-services.json;
  // gated in try/catch so a build without the config still runs.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('Firebase init skipped: $error');
  }

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

    // Settle a possibly-expired persisted session BEFORE the UI mounts and
    // fires authed calls, so the first request doesn't 401 mid-first-render
    // (the cold-start race, CLAUDE.md §11). Best-effort: a transient/offline
    // failure keeps the existing session — the 401 interceptor signs the user
    // out only on a definitive auth failure, so a flaky launch isn't punished.
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session != null && session.isExpired) {
      try {
        await auth.refreshSession();
      } catch (error) {
        debugPrint('Session refresh on startup skipped: $error');
      }
    }
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
  runApp(const ProviderScope(child: FashionOsApp(enablePush: true)));
}
