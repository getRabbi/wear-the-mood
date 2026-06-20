import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/offers/offers_view.dart';
import 'package:app/l10n/app_localizations.dart';

/// Issue 2: Offers is its own browsable Community section (not a Newsroom strip).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final offer = Offer.fromJson({
    'id': 'o1',
    'title': '40% off knitwear',
    'brand': 'Studio Label',
    'image_url': null, // avoids a network fetch in the test
    'discount_label': '-40%',
    'affiliate_url': 'https://x.com/p?utm_source=fashionos',
    'topics': <String>[],
  });

  Widget wrap(List<Offer> offers) => ProviderScope(
        overrides: [offersProvider.overrideWith((ref) async => offers)],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: OffersView()),
        ),
      );

  testWidgets('lists offer deals with a shop CTA + section header', (tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap([offer]));
    await tester.pump(); // resolve the offers future

    expect(find.text('40% off knitwear'), findsOneWidget);
    expect(find.text('Shop deal'), findsOneWidget); // affiliate CTA
    expect(find.text('Offers'), findsOneWidget); // section header
  });

  testWidgets('shows the empty state when there are no offers', (tester) async {
    await tester.pumpWidget(wrap(const []));
    await tester.pump();

    expect(find.text('No offers right now'), findsOneWidget);
  });
}
