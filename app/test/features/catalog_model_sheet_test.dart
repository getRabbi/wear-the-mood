import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/studio/catalog_model_sheet.dart';
import 'package:app/l10n/app_localizations.dart';

const _item = WardrobeItem(id: 'w1', title: 'Tee', imageUrl: 'https://x/1');

Credits _credits({required String tier, required bool hd}) => Credits(
  balance: 10, dailyFreeUsed: 0, dailyFreeLimit: 3, dailyFreeRemaining: 3,
  totalAvailable: 10, tier: tier, hdAllowed: hd,
);

Widget _host({required Credits credits}) => ProviderScope(
  overrides: [creditsProvider.overrideWith((ref) async => credits)],
  child: MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showCatalogModelSheet(context, _item),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('catalog sheet shows all five model styles + quality', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(credits: _credits(tier: 'pro_max', hd: true)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Catalog Model Shot'), findsOneWidget);
    for (final s in ['Studio', 'Streetwear', 'Modest', 'Luxury', 'Cropped face']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text('Pro Standard'), findsOneWidget);
    expect(find.text('Pro Max HD'), findsOneWidget);
  });

  testWidgets('Pro Max HD is locked for a Pro (non-Pro-Max) user', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(credits: _credits(tier: 'pro', hd: false)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The HD quality card carries a lock for a plan without hd_allowed.
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });
}
