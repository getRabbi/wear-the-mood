import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/repositories/outfit_repository.dart';
import 'package:app/features/outfits/outfit_collage.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/outfits/outfits_screen.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

/// Records deletes so the long-press flow can be asserted without a network.
class _FakeOutfitRepository implements OutfitRepository {
  final List<String> deleted = [];

  @override
  Future<List<Outfit>> getOutfits() async => const [];

  @override
  Future<Outfit> createOutfit({
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async => Outfit(id: 'new', name: name, itemIds: itemIds);

  @override
  Future<Outfit> updateOutfit(
    String id, {
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async => Outfit(id: id, name: name, itemIds: itemIds);

  @override
  Future<void> deleteOutfit(String id) async => deleted.add(id);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget app() => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const OutfitsScreen(),
  );

  testWidgets('renders a grid of outfits with name + piece count', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          outfitsProvider.overrideWith(
            (ref) async => const [
              Outfit(
                id: 'o1',
                name: 'Friday',
                itemIds: ['w1', 'w2'],
                coverImageUrl: 'https://x/1',
              ),
            ],
          ),
          wardrobeItemsProvider.overrideWith((ref) async => const []),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.byType(OutfitCollageCard), findsOneWidget);
    expect(find.text('Friday'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // piece-count badge
  });

  testWidgets('shows the empty state when there are no outfits', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [outfitsProvider.overrideWith((ref) async => const [])],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.text('No outfits yet'), findsOneWidget);
    expect(find.text('Create outfit'), findsWidgets);
  });

  testWidgets('shows a shimmer grid while loading', (tester) async {
    final never = Completer<List<Outfit>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [outfitsProvider.overrideWith((ref) => never.future)],
        child: app(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoadingShimmer), findsWidgets);
  });

  testWidgets('long-press → confirm removes the outfit', (tester) async {
    final fake = _FakeOutfitRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          outfitsProvider.overrideWith(
            (ref) async => const [
              Outfit(id: 'o1', name: 'Friday', itemIds: ['w1']),
            ],
          ),
          wardrobeItemsProvider.overrideWith((ref) async => const []),
          outfitRepositoryProvider.overrideWithValue(fake),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    await tester.longPress(find.byType(OutfitCollageCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Remove this outfit?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump();

    expect(fake.deleted, ['o1']);
    expect(find.text('Outfit removed'), findsOneWidget);
  });
}
