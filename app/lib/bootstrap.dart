import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/secure_local_storage.dart';
import 'core/env/app_env.dart';

/// Central app initialization. `main.dart` stays a thin entrypoint so all
/// SDK/platform setup lives in one place.
///
/// Remaining wiring (kept as TODOs to avoid building ahead):
/// - Step 10: initialize Sentry (runZonedGuarded) + PostHog.
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

  runApp(
    const ProviderScope(
      child: FashionOsApp(),
    ),
  );
}
