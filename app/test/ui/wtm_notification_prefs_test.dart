import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/data/models/notification_prefs.dart';
import 'package:app/data/repositories/notification_prefs_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/ui/notifications/wtm_notification_prefs_screen.dart';

class _FakeRepo implements NotificationPrefsRepository {
  Map<String, bool>? lastUpdate;
  NotificationPreferences current = const NotificationPreferences();

  @override
  Future<NotificationPreferences> get() async => current;

  @override
  Future<NotificationPreferences> update(Map<String, bool> changes) async {
    lastUpdate = changes;
    var p = current;
    changes.forEach((k, v) {
      p = switch (k) {
        'social' => p.copyWith(social: v),
        'promotions' => p.copyWith(promotions: v),
        _ => p,
      };
    });
    current = p;
    return p;
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, {NotificationPreferences? prefs}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final repo = _FakeRepo()..current = prefs ?? const NotificationPreferences();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationPrefsRepositoryProvider.overrideWithValue(repo),
        notificationPrefsProvider.overrideWith((ref) async => repo.current),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WtmNotificationPrefsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('renders every category toggle', (tester) async {
    await _pump(tester);
    expect(find.text('Social activity'), findsOneWidget);
    expect(find.text('Referral rewards'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Daily style reminders'), findsOneWidget);
    expect(find.text('Product news & offers'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(6));
  });

  testWidgets('promotions default off; others on', (tester) async {
    await _pump(tester);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    // Order matches the screen: social, referral, account, community, style, promotions.
    expect(switches.first.value, isTrue); // social on
    expect(switches.last.value, isFalse); // promotions off (opt-in)
  });

  testWidgets('toggling a category PATCHes that category only', (tester) async {
    final repo = await _pump(tester);
    // Tap the social switch (first) off.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repo.lastUpdate, {'social': false});
  });
}
