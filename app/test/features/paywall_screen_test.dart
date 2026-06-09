import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/paywall/paywall_screen.dart';
import 'package:app/l10n/app_localizations.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PaywallScreen(),
    ),
  );

  testWidgets('renders plans and defaults to the best-value plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Unlock everything'), findsOneWidget);
    expect(find.text('Unlimited try-ons'), findsOneWidget);
    expect(find.text(r'$59.99'), findsOneWidget);
    expect(find.text(r'$8.99'), findsOneWidget);
    expect(find.text('Start free trial'), findsOneWidget);
    // Default selection is the annual (best-value) plan.
    expect(find.textContaining(r'then $59.99'), findsOneWidget);
  });

  testWidgets('selecting the monthly plan updates the trial note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text(r'$8.99'));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'then $8.99'), findsOneWidget);
  });
}
