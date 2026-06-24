import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/outfits/outfit_detail_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

/// Issue 9: tapping an outfit opens a detail view showing ALL its pieces — not
/// the editor. These pump the detail screen directly with a stubbed closet.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const closet = [
    WardrobeItem(id: 'w1', title: 'White tee', imageUrl: 'https://x/1', cutoutStatus: 'done'),
    WardrobeItem(id: 'w2', title: 'Black jeans', imageUrl: 'https://x/2', cutoutStatus: 'done'),
  ];

  Widget app(Outfit outfit, {List<WardrobeItem> items = closet}) => ProviderScope(
    overrides: [
      wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(items)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OutfitDetailScreen(outfit: outfit),
    ),
  );

  testWidgets('shows every piece in the outfit + a Try-full-look CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const Outfit(id: 'o1', name: 'Friday', itemIds: ['w1', 'w2'])),
    );
    await tester.pump();

    expect(find.text('Friday'), findsOneWidget); // title
    expect(find.text('White tee'), findsOneWidget); // both pieces shown
    expect(find.text('Black jeans'), findsOneWidget);
    expect(find.text('Try full look'), findsOneWidget); // deliberate action
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget); // edit is opt-in
  });

  testWidgets('shows a missing-pieces state when items are gone', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Outfit(id: 'o1', name: 'Old', itemIds: ['gone1', 'gone2']),
      ),
    );
    await tester.pump();

    expect(find.text('Pieces no longer in your closet'), findsOneWidget);
  });
}
