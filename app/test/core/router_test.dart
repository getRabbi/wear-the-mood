import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/features/auth/welcome_screen.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/onboarding/onboarding_screen.dart';
import 'package:app/features/wardrobe/wardrobe_screen.dart';

void main() {
  // Avoid network font fetches during tests; fall back to the default font.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('goRouterProvider provides a GoRouter starting at home', () {
    final container = ProviderContainer(
      overrides: [isAuthenticatedProvider.overrideWithValue(false)],
    );
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);

    expect(router, isA<GoRouter>());
    expect(router.routeInformationProvider.value.uri.path, AppRoute.home);
  });

  testWidgets(
    'logged out: a deep link to a protected route redirects to the gate',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          isAuthenticatedProvider.overrideWithValue(false),
          onboardingSeenProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FashionOsApp(),
        ),
      );
      await tester.pump();

      // Attempt to reach gated content while signed out.
      container.read(goRouterProvider).go(AppRoute.wardrobe);
      await tester.pump();
      await tester.pump();

      // Bounced to the welcome gate — the closet never renders.
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(WardrobeScreen), findsNothing);
    },
  );

  testWidgets('logged out, first run: shows the onboarding carousel at /', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
