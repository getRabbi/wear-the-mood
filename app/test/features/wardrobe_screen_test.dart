import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/features/wardrobe/wardrobe_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const WardrobeScreen(),
  );

  testWidgets('renders a grid of pieces when the closet has items', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeItemsProvider.overrideWith(
            (ref) async => const [
              WardrobeItem(
                id: 'w1',
                title: 'White tee',
                imageUrl: 'https://x/1',
              ),
              WardrobeItem(
                id: 'w2',
                title: 'Black jeans',
                imageUrl: 'https://x/2',
              ),
            ],
          ),
        ],
        child: app(),
      ),
    );
    await tester.pump(); // resolve the future; no settle (infinite shimmer)

    expect(find.byType(OutfitTile), findsNWidgets(2));
    expect(find.text('White tee'), findsOneWidget);
  });

  testWidgets('shows the empty state when the closet is empty', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeItemsProvider.overrideWith((ref) async => const []),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.text('Your closet is empty'), findsOneWidget);
    expect(find.text('Add a piece'), findsOneWidget);
  });

  testWidgets('shows a shimmer grid while loading', (tester) async {
    final never = Completer<List<WardrobeItem>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [wardrobeItemsProvider.overrideWith((ref) => never.future)],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingShimmer), findsWidgets);
  });
}
