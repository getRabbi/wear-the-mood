import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env/app_env.dart';
import 'analytics.dart';

/// Provides [PostHogAnalytics] when a PostHog key is configured, otherwise a
/// [NoopAnalytics] so calls are safe everywhere.
final analyticsProvider = Provider<Analytics>((ref) {
  return AppEnv.posthogApiKey.isNotEmpty
      ? const PostHogAnalytics()
      : const NoopAnalytics();
});
