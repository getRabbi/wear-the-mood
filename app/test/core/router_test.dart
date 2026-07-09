import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/auth/welcome_screen.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_screen.dart';
import 'package:app/ui/auth/wtm_auth_screen.dart';
import 'package:app/ui/closet/wtm_closet_screen.dart';
import 'package:app/ui/shell/wtm_shell.dart';

/// WTM cutover auth gate (URGENT mobile-QA regression): the WTM Atelier shell
/// is the ONLY active shell — signed-out users land on the WTM auth gate
/// (protected screens never mount, so no API call can fire with a null bearer
/// token), and login/logout/legacy entries always resolve back into WTM.
/// Mutable auth flag so one test can sign out + back in (the router's
/// refreshListenable re-runs the redirect on every flip).
class _AuthFlag extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}

final _authFlag = NotifierProvider<_AuthFlag, bool>(_AuthFlag.new);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required bool loggedIn,
    bool mutableAuth = false,
  }) async {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        mutableAuth
            ? isAuthenticatedProvider.overrideWith(
                (ref) => ref.watch(_authFlag),
              )
            : isAuthenticatedProvider.overrideWithValue(loggedIn),
        onboardingSeenProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);
    if (mutableAuth) {
      container.read(_authFlag.notifier).set(loggedIn);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    // Through the WTM splash (700ms orb beat) and its auth routing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  test('router defaults to the WTM splash (cutover entry)', () {
    final container = ProviderContainer(
      overrides: [isAuthenticatedProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);
    expect(router, isA<GoRouter>());
    expect(router.routeInformationProvider.value.uri.path, AppRoute.wtmSplash);
  });

  testWidgets('GATE: authenticated startup lands in the WTM shell', (
    tester,
  ) async {
    await boot(tester, loggedIn: true);

    expect(find.byType(WtmShell), findsOneWidget);
    // The legacy Fashion OS shell never appears.
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('GATE: signed-out startup lands on the WTM auth gate', (
    tester,
  ) async {
    await boot(tester, loggedIn: false);

    expect(find.byType(WtmAuthScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(WtmShell), findsNothing);
  });

  testWidgets(
    'GATE: signed-out deep links to protected routes bounce to WTM auth '
    '(protected screens never mount → no null-bearer API calls)',
    (tester) async {
      final container = await boot(tester, loggedIn: false);

      // A protected WTM route.
      container.read(goRouterProvider).go(AppRoute.wtmCloset);
      await tester.pump();
      await tester.pump();
      expect(find.byType(WtmAuthScreen), findsOneWidget);
      expect(find.byType(WtmClosetScreen), findsNothing);

      // A protected LEGACY route bounces into WTM too — never the old gate.
      container.read(goRouterProvider).go(AppRoute.wardrobe);
      await tester.pump();
      await tester.pump();
      expect(find.byType(WtmAuthScreen), findsOneWidget);
      expect(find.byType(WardrobeScreen), findsNothing);
      expect(find.byType(WelcomeScreen), findsNothing);
    },
  );

  testWidgets('GATE: logout → WTM auth; login again → WTM shell, never legacy',
      (tester) async {
    final container = await boot(tester, loggedIn: true, mutableAuth: true);
    expect(find.byType(WtmShell), findsOneWidget);

    // Sign out → the redirect kicks to the WTM auth gate. Pump through the
    // route transition in discrete frames (the orb/aurora animate forever, so
    // pumpAndSettle would never return) and let the shell teardown finish
    // before flipping back (go_router reuses the shell's GlobalKey).
    Future<void> throughTransition() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
    }

    container.read(_authFlag.notifier).set(false);
    await throughTransition();
    expect(find.byType(WtmAuthScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);

    // Sign back in → straight back into the WTM shell, not the old UI.
    container.read(_authFlag.notifier).set(true);
    await throughTransition();
    expect(find.byType(WtmShell), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('GATE: legacy shell entries resolve to WTM for signed-in users',
      (tester) async {
    final container = await boot(tester, loggedIn: true);

    for (final legacyEntry in [AppRoute.home, AppRoute.auth]) {
      container.read(goRouterProvider).go(legacyEntry);
      await tester.pump();
      await tester.pump();
      expect(find.byType(WtmShell), findsOneWidget,
          reason: '$legacyEntry must land in the WTM shell');
      expect(find.byType(HomeScreen), findsNothing);
    }
  });
}
