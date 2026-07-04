import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/theme/wtm_colors.dart';
import 'package:app/ui/home/wtm_home_screen.dart';
import 'package:app/ui/home/wtm_mood.dart';
import 'package:app/ui/discover/wtm_inbox_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// P2 gate coverage: mood persistence + Today's-Look reseeding + bell→Inbox
/// (§3.1 amendments, §8 Home rows). Visual fidelity is the on-device pixel
/// pass against board 01.
class _FakeMoodRepo implements WtmMoodRepository {
  _FakeMoodRepo([this.value]);

  double? value;
  int writes = 0;

  @override
  Future<double?> read() async => value;

  @override
  Future<void> write(double v) async {
    value = v;
    writes++;
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required _FakeMoodRepo moodRepo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      // The bell lands on the real Inbox, which fetches notifications over the
      // network here — disable the backoff retry so it never trips teardown.
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        wtmMoodRepositoryProvider.overrideWithValue(moodRepo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmHome);
    await settle(tester);
    return container;
  }

  Color? labelColor(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style?.color;

  testWidgets('mood drag recolors the zone label, reseeds Today\'s Look, '
      'and persists on release', (tester) async {
    final repo = _FakeMoodRepo();
    final container = await boot(tester, moodRepo: repo);

    // Board resting state: 0.36 → Confident zone, Moonlit Confidence look.
    expect(labelColor(tester, 'Confident'), WtmColors.gold);
    expect(labelColor(tester, 'Rebel'), isNot(WtmColors.gold));
    expect(
      find.textContaining('Confidence', findRichText: true),
      findsWidgets,
    );

    // Drag the knob far right → Rebel zone (stepped, like a real finger).
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(WtmSlider)));
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(container.read(wtmMoodProvider), greaterThan(0.75));
    expect(labelColor(tester, 'Rebel'), WtmColors.gold);
    expect(labelColor(tester, 'Confident'), isNot(WtmColors.gold));
    expect(
      find.textContaining('Rebellion', findRichText: true),
      findsWidgets,
    );

    // Released → persisted.
    expect(repo.writes, greaterThan(0));
    expect(repo.value, container.read(wtmMoodProvider));
  });

  testWidgets('persisted mood restores on a fresh session', (tester) async {
    final repo = _FakeMoodRepo(0.9); // saved as Rebel previously
    await boot(tester, moodRepo: repo);
    await tester.pump(); // restore microtask → state → rebuild

    expect(labelColor(tester, 'Rebel'), WtmColors.gold);
    expect(
      find.textContaining('Rebellion', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('bell routes to Inbox; home renders greeting without a session',
      (tester) async {
    await boot(tester, moodRepo: _FakeMoodRepo());
    // Guest (no Supabase session in tests): greeting shows without a name.
    expect(find.textContaining('Good '), findsOneWidget);

    await tester.tap(find.byType(WtmIconButton).first); // apphead bell
    await settle(tester);
    expect(find.byType(WtmInboxScreen), findsOneWidget);
    expect(find.byType(WtmHomeScreen), findsNothing); // switched branch
  });
}
