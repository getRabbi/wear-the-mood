import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget wrap({List<WardrobeItem> closet = _closet}) => ProviderScope(
    overrides: [
      creditsProvider.overrideWith(
        (ref) async => const Credits(
          balance: 0,
          dailyFreeUsed: 0,
          dailyFreeLimit: 5,
          dailyFreeRemaining: 5,
        ),
      ),
      avatarSignedUrlProvider.overrideWith((ref) async => null),
      // The garment picker is the user's wardrobe.
      wardrobeItemsProvider.overrideWith((ref) async => closet),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const TryOnScreen(),
    ),
  );

  // The "Generate your look" CTA in the sticky bottom bar.
  PrimaryButton cta(WidgetTester tester) => tester.widget<PrimaryButton>(
    find.ancestor(
      of: find.text('Generate 2D preview'),
      matching: find.byType(PrimaryButton),
    ),
  );

  testWidgets('picks a garment from the wardrobe; CTA enables on select', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.text('Generate 2D preview'), findsOneWidget);
    // The two closet pieces show in the clothing picker.
    expect(find.byType(SmartImageCard), findsNWidgets(2));
    expect(cta(tester).onPressed, isNull);

    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(cta(tester).onPressed, isNotNull);
  });

  testWidgets('empty wardrobe shows an add-clothes prompt, CTA disabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(closet: const []));
    await tester.pump();

    expect(find.text('Add clothes'), findsOneWidget);
    expect(cta(tester).onPressed, isNull);
  });
}

const _closet = [
  WardrobeItem(
    id: 'w1',
    title: 'White tee',
    imageUrl: 'https://x/1',
    cutoutStatus: 'done',
  ),
  WardrobeItem(
    id: 'w2',
    title: 'Black jeans',
    imageUrl: 'https://x/2',
    cutoutStatus: 'done',
  ),
];
