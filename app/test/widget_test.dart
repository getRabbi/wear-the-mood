import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';

void main() {
  // Avoid network font fetches during tests; fall back to the default font.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('App renders the home screen with the try-on hook', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Skip onboarding so the gate lands on the app shell.
          onboardingSeenProvider.overrideWith((ref) => true),
          // Logged in → the auth gate opens to the full app (RootGate/router).
          isAuthenticatedProvider.overrideWithValue(true),
          // The shell eagerly builds the Profile tab, which reads auth state.
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
    // Single pump only — the screen has infinite shimmer/spinner animations so
    // pumpAndSettle would never return.
    await tester.pump();

    expect(find.text('Your AI stylist is ready'), findsOneWidget);
    expect(find.text('Open MoodMirror'), findsOneWidget);
  });
}
