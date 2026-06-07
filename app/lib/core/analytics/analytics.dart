import 'package:posthog_flutter/posthog_flutter.dart';

/// Analytics facade so feature code never touches the PostHog SDK directly
/// (CLAUDE.md §15). Use [AnalyticsEvents] for event names.
abstract interface class Analytics {
  Future<void> track(String event, {Map<String, Object>? properties});
  Future<void> identify(String userId);
  Future<void> reset();
}

/// No-op implementation used when PostHog isn't configured (dev without a key)
/// or in tests.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) async {}

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
}

/// PostHog-backed analytics. Requires `Posthog().setup(...)` to have run in
/// `bootstrap()` (only happens when an API key is configured).
class PostHogAnalytics implements Analytics {
  const PostHogAnalytics();

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) =>
      Posthog().capture(eventName: event, properties: properties);

  @override
  Future<void> identify(String userId) => Posthog().identify(userId: userId);

  @override
  Future<void> reset() => Posthog().reset();
}
