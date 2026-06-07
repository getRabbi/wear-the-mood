import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/analytics/analytics.dart';
import 'package:app/core/analytics/analytics_events.dart';

void main() {
  test('NoopAnalytics methods complete without error', () async {
    const analytics = NoopAnalytics();
    await analytics.track(
      AnalyticsEvents.appOpened,
      properties: {'source': 'test'},
    );
    await analytics.identify('user-1');
    await analytics.reset();
  });

  test('event names follow snake_case noun_verb', () {
    const names = <String>[
      AnalyticsEvents.appOpened,
      AnalyticsEvents.tryonStarted,
      AnalyticsEvents.wardrobeItemAdded,
      AnalyticsEvents.subscriptionStarted,
      AnalyticsEvents.accountDeleted,
    ];
    final pattern = RegExp(r'^[a-z]+(_[a-z]+)+$');
    for (final name in names) {
      expect(pattern.hasMatch(name), isTrue, reason: name);
    }
  });
}
