import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/outfit_repository.dart';
import 'package:app/features/outfits/create_outfit_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import '../helpers/fake_wardrobe_items.dart';

/// Records the create call so the save flow can be asserted without a network.
class _FakeOutfitRepository implements OutfitRepository {
  List<String>? createdItemIds;
  String? createdCover;
  String? createdName;

  @override
  Future<List<Outfit>> getOutfits() async => const [];

  @override
  Future<Outfit> createOutfit({
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async {
    createdName = name;
    createdItemIds = itemIds;
    createdCover = coverImageUrl;
    return Outfit(id: 'new', name: name, itemIds: itemIds);
  }

  @override
  Future<Outfit> updateOutfit(
    String id, {
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async {
    createdName = name;
    createdItemIds = itemIds;
    createdCover = coverImageUrl;
    return Outfit(id: id, name: name, itemIds: itemIds);
  }

  @override
  Future<void> deleteOutfit(String id) async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // A tiny router so the screen's context.pop() resolves after saving.
  GoRouter router({String initial = '/create'}) => GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(path: '/create', builder: (_, _) => const CreateOutfitScreen()),
    ],
  );

  Widget app(GoRouter r) => MaterialApp.router(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: r,
  );

  testWidgets('save is disabled until a piece is selected, then it posts', (
    tester,
  ) async {
    final fake = _FakeOutfitRepository();
    // Start at home and push /create so pop() has somewhere to return to.
    final r = router(initial: '/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(const [
              WardrobeItem(
                id: 'w1',
                title: 'White tee',
                imageUrl: 'https://x/1',
              ),
            ])),
          outfitRepositoryProvider.overrideWithValue(fake),
        ],
        child: app(r),
      ),
    );
    await tester.pump();
    r.push('/create');
    await tester.pump(); // start the push transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it
    await tester.pump(); // resolve the wardrobe future

    // Nothing selected yet → tapping Save is a no-op.
    await tester.tap(find.text('Save outfit'));
    await tester.pump();
    expect(fake.createdItemIds, isNull);

    // Add a piece to the "Top" slot: tap the slot → pick from the closet sheet.
    await tester.tap(find.text('Top'));
    await tester.pump(); // start the sheet open
    await tester.pump(const Duration(milliseconds: 400)); // finish it
    await tester.tap(find.byType(SmartImageCard).first);
    await tester.pump(); // start the sheet close
    await tester.pump(const Duration(milliseconds: 400)); // finish it

    // Now save.
    await tester.tap(find.text('Save outfit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(fake.createdItemIds, ['w1']);
    expect(fake.createdCover, 'https://x/1');
    expect(fake.createdName, isNull); // no name entered
    expect(find.text('home'), findsOneWidget); // popped back
  });

  testWidgets('shows the empty state when the wardrobe is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier(const [])),
        ],
        child: app(router()),
      ),
    );
    await tester.pump();

    expect(find.text('Your closet is empty'), findsOneWidget);
  });
}
