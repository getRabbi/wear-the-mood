import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/onboarding/root_gate.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const RootGate(),
  );

  testWidgets('shows onboarding when not yet completed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingSeenProvider.overrideWith((ref) => false)],
        child: app(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('See it on you'), findsOneWidget);
  });

  testWidgets('shows the app when onboarding is complete', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingSeenProvider.overrideWith((ref) => true),
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 0,
              dailyFreeUsed: 0,
              dailyFreeLimit: 5,
              dailyFreeRemaining: 5,
            ),
          ),
          wardrobeItemsProvider.overrideWith(
            (ref) async => const <WardrobeItem>[],
          ),
        ],
        child: app(),
      ),
    );
    await tester.pump();
    expect(find.text('Start a try-on'), findsOneWidget);
  });

  testWidgets('shows a splash while the flag is loading', (tester) async {
    final never = Completer<bool>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [onboardingSeenProvider.overrideWith((ref) => never.future)],
        child: app(),
      ),
    );
    await tester.pump();
    expect(find.text('See it on you'), findsNothing);
    expect(find.text('Start a try-on'), findsNothing);
  });
}
