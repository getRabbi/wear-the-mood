import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/shell/wtm_shell.dart';

void main() {
  // Avoid network font fetches during tests; fall back to the default font.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('App boots through the WTM splash into the WTM shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Skip onboarding so the gate lands on the app shell.
          onboardingSeenProvider.overrideWith((ref) => true),
          // Logged in → the cutover gate opens straight into the WTM shell.
          isAuthenticatedProvider.overrideWithValue(true),
          // The shell eagerly builds tabs that read auth + credits state.
          signedInEmailProvider.overrideWithValue(null),
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 0,
              dailyFreeUsed: 0,
              dailyFreeLimit: 5,
              dailyFreeRemaining: 5,
            ),
          ),
        ],
        child: const FashionOsApp(),
      ),
    );
    // Discrete pumps only — the orb/shimmer animate forever, so pumpAndSettle
    // would never return. Ride through the splash beat + its routing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    // The WTM Atelier shell is the app (mobile-QA cutover) — the legacy
    // Fashion OS home never renders.
    expect(find.byType(WtmShell), findsOneWidget);
    expect(find.text('Your AI stylist is ready'), findsNothing);
  });
}
