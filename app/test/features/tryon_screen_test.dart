import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap() => ProviderScope(
    overrides: [
      creditsProvider.overrideWith(
        (ref) async => const Credits(
          balance: 0,
          dailyFreeUsed: 0,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 5,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  FilledButton cta(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('shows the picker; CTA stays disabled until a piece is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Pick a piece'), findsOneWidget);
    expect(find.text('Try it on'), findsOneWidget);
    expect(find.text('Linen shirt'), findsWidgets);
    expect(cta(tester).onPressed, isNull);

    // Tap the tile image (the label sits below the 600px test viewport).
    await tester.tap(find.byType(OutfitTile).first);
    await tester.pump();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });
}
