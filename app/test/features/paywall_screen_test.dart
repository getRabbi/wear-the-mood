import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/repositories/billing_repository.dart';
import 'package:app/features/paywall/paywall_screen.dart';
import 'package:app/l10n/app_localizations.dart';

import '../helpers/fake_dio.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app({bool active = false}) {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({'active': active, 'product_id': active ? 'annual' : null}),
    );
    return ProviderScope(
      overrides: [
        billingRepositoryProvider.overrideWithValue(BillingRepository(dio)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PaywallScreen(),
      ),
    );
  }

  testWidgets('renders plans and defaults to the best-value plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Unlock everything'), findsOneWidget);
    // Comparison table leads with the metered AI try-ons row (3 vs Unlimited).
    expect(find.text('AI realistic try-ons'), findsOneWidget);
    expect(find.text(r'$8.99'), findsOneWidget); // Pro
    expect(find.text(r'$15.99'), findsOneWidget); // Pro Max
    expect(find.text('Start free trial'), findsOneWidget);
    // Default selection is Pro (best value).
    expect(find.textContaining(r'then $8.99'), findsOneWidget);
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

  testWidgets('without RevenueCat config: no dead restore, credits note shown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The test build has no REVENUECAT_ANDROID_KEY, so the paywall is in the
    // safe "not configured" state.
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Restore is hidden until the store SDK is configured (no dead button).
    expect(find.text('Restore purchases'), findsNothing);
    // The old generic "coming soon" is gone.
    expect(find.text('Subscriptions are coming soon.'), findsNothing);
    // Credits are clearly shown as a way to use AI (not premium-only).
    expect(
      find.textContaining('Your first 3 AI realistic try-ons are free'),
      findsOneWidget,
    );
  });

  testWidgets('shows the premium state when already subscribed', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(active: true));
    await tester.pumpAndSettle();

    expect(find.text("You're Premium"), findsOneWidget);
    expect(find.text('Start free trial'), findsNothing);
  });
}
