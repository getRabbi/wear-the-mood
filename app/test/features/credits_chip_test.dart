import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/credits/credits_chip.dart';
import 'package:app/l10n/app_localizations.dart';

Widget _app() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(body: Center(child: CreditsChip())),
);

void main() {
  testWidgets('shows total available credits including the free trial', (
    tester,
  ) async {
    // A free user with 3 trial try-ons left has total_available = 3; the chip
    // shows the real total (not just "free"), so a later top-up is never hidden.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 0,
              dailyFreeUsed: 2,
              dailyFreeLimit: 5,
              dailyFreeRemaining: 3,
              totalAvailable: 3,
            ),
          ),
        ],
        child: _app(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 credits'), findsOneWidget);
  });

  testWidgets('shows paid balance when present', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 7,
              dailyFreeUsed: 5,
              dailyFreeLimit: 5,
              dailyFreeRemaining: 0,
              tier: 'pro',
              totalAvailable: 7,
            ),
          ),
        ],
        child: _app(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 credits'), findsOneWidget);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final never = Completer<Credits>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [creditsProvider.overrideWith((ref) => never.future)],
        child: _app(),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
