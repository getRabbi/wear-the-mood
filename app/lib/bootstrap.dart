import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Central app initialization. `main.dart` stays a thin entrypoint so all
/// SDK/platform setup lives in one place.
///
/// Wiring added in later steps (kept as TODOs to avoid building ahead):
/// - Step 9:  initialize Supabase from [AppEnv] + auth/token refresh.
/// - Step 10: initialize Sentry (runZonedGuarded) + PostHog.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: FashionOsApp(),
    ),
  );
}
