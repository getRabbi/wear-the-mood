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
        'account_updates' => p.copyWith(accountUpdates: v),
        'referral_rewards' => p.copyWith(referralRewards: v),
        'social_activity' => p.copyWith(socialActivity: v),
        'community' => p.copyWith(community: v),
        'daily_style' => p.copyWith(dailyStyle: v),
        'product_updates' => p.copyWith(productUpdates: v),
        'promotional' => p.copyWith(promotional: v),
        _ => p,
      };
    });
    current = p;
    return p;
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, {NotificationPreferences? prefs}) async {
  tester.view.physicalSize = const Size(1080, 3800);
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

  testWidgets('renders all seven category toggles', (tester) async {
    await _pump(tester);
    expect(find.text('Account & billing'), findsOneWidget);
    expect(find.text('Referral rewards'), findsOneWidget);
    expect(find.text('Social activity'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Daily style reminders'), findsOneWidget);
    expect(find.text('Product news'), findsOneWidget);
    expect(find.text('Offers & promotions'), findsOneWidget);
    // Exactly seven switches — the master status row uses a button, not a switch.
    expect(find.byType(Switch), findsNWidgets(7));
  });

  testWidgets('promotional defaults off; account defaults on', (tester) async {
    await _pump(tester);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    // Order: account, referral, social, community, daily_style, product, promotional.
    expect(switches.first.value, isTrue); // account_updates on
    expect(switches.last.value, isFalse); // promotional off (opt-in)
  });

  testWidgets('shows the in-app-center reassurance copy', (tester) async {
    await _pump(tester);
    expect(
      find.text(
        'Muted categories will still remain available in your in-app '
        'notification center.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('toggling a category PATCHes that category only', (tester) async {
    final repo = await _pump(tester);
    // Tap the first switch (account_updates) off.
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repo.lastUpdate, {'account_updates': false});
  });

  testWidgets('promotional can be opted in', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(repo.lastUpdate, {'promotional': true});
  });
}
