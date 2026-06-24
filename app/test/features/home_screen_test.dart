import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('home shows the try-on hook, closet section and stylist teaser', (
    tester,
  ) async {
    // Tall surface so the lazily-built sections below the hero are realized.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsProvider.overrideWith(
            (ref) async => const Credits(
              balance: 0,
              dailyFreeUsed: 0,
              dailyFreeLimit: 5,
              dailyFreeRemaining: 5,
            ),
          ),
          wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(const <WardrobeItem>[])),
          signedInEmailProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Open MoodMirror'), findsOneWidget);
    expect(find.text('Your closet'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    // The stylist teaser is now a Home quick action.
    expect(find.text("Today's stylist"), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets(
    'closet preview shows the category (not "Uncategorized") for a '
    'categorized item with no name',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditsProvider.overrideWith(
              (ref) async => const Credits(
                balance: 0,
                dailyFreeUsed: 0,
                dailyFreeLimit: 5,
                dailyFreeRemaining: 5,
              ),
            ),
            // Categorized as "Tops" but never given a custom name.
            wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(const <WardrobeItem>[
                WardrobeItem(
                  id: 'w1',
                  category: 'Tops',
                  imageUrl: 'https://x/1',
                ),
              ])),
            signedInEmailProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();

      // The card reflects the saved category, not a stale "Uncategorized".
      expect(find.text('Tops'), findsOneWidget);
      expect(find.text('Uncategorized'), findsNothing);
    },
  );
}
