import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/studio_model_preset.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/ai_studio_repository.dart';
import 'package:app/data/repositories/credits_repository.dart';
import 'package:app/features/profile/avatar_service.dart';
import 'package:app/features/tryon/tryon_screen.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import '../helpers/fake_wardrobe_items.dart';

const _closet = [
  WardrobeItem(
    id: 'w1', title: 'White tee', category: 'top',
    imageUrl: 'https://x/1', cutoutStatus: 'done',
  ),
];

const _preset = StudioModelPreset(
  id: 'sm1', name: 'Female Studio', imageUrl: 'https://x/model.jpg',
  style: 'female_studio', isProOnly: false,
);
const _freeModel = StudioModelPreset(
  id: 'f', name: 'Female Studio', imageUrl: 'https://x/f.jpg',
  style: 'female_studio', isProOnly: false,
);
const _proModel = StudioModelPreset(
  id: 'p', name: 'Curve Model', imageUrl: 'https://x/c.jpg',
  style: 'curve', isProOnly: true,
);

Credits _credits({required String tier}) => Credits(
  balance: 10, dailyFreeUsed: 0, dailyFreeLimit: 3, dailyFreeRemaining: 3,
  totalAvailable: 10, tier: tier, hdAllowed: tier == 'pro_max',
);

Widget _wrap({
  required String tier,
  List<StudioModelPreset> models = const [_preset],
}) => ProviderScope(
  overrides: [
    creditsProvider.overrideWith((ref) async => _credits(tier: tier)),
    avatarSignedUrlProvider.overrideWith((ref) async => null),
    wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(_closet)),
    studioModelsProvider.overrideWith((ref) async => models),
  ],
  child: MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const TryOnScreen(),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('body source toggle shows My photo + Studio model', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(tier: 'pro'));
    await tester.pump();

    expect(find.text('My photo'), findsOneWidget);
    expect(find.text('Studio model'), findsOneWidget);
  });

  testWidgets('subscriber sees the studio model picker after switching', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(tier: 'pro'));
    await tester.pump();

    await tester.tap(find.text('Studio model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // resolve the future

    // The active preset is offered (and NOT the locked Pro notice).
    expect(find.text('Female Studio'), findsOneWidget);
    expect(find.text('Studio models are a Pro feature'), findsNothing);
  });

  testWidgets('free user: free model selectable, Pro-only model locked', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(tier: 'free', models: const [_freeModel, _proModel]));
    await tester.pump();

    await tester.tap(find.text('Studio model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // No whole-segment lock: both models show; only the Pro-only one is locked.
    expect(find.text('Studio models are a Pro feature'), findsNothing);
    expect(find.text('Female Studio'), findsOneWidget); // free model
    expect(find.text('Curve Model'), findsOneWidget); // pro-only model
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget); // exactly the pro one
  });

  testWidgets('empty studio list shows coming soon for a subscriber', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(tier: 'pro', models: const []));
    await tester.pump();

    await tester.tap(find.text('Studio model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Studio models are coming soon.'), findsOneWidget);
  });
}
