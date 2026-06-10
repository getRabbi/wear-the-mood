import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/core/theme/app_theme.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/features/wardrobe/wardrobe_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/shared/widgets/widgets.dart';

/// Records deletes so the long-press flow can be asserted without a network.
class _FakeWardrobeRepository implements WardrobeRepository {
  final List<String> deleted = [];

  @override
  Future<List<WardrobeItem>> getItems() async => const [];

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    required String imageUrl,
  }) async => WardrobeItem(id: 'new', title: title, imageUrl: imageUrl);

  @override
  Future<void> deleteItem(String id) async => deleted.add(id);
}

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

  testWidgets('shows a processing badge while a cutout is generating', (
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
                cutoutStatus: 'processing',
              ),
              WardrobeItem(
                id: 'w2',
                title: 'Black jeans',
                imageUrl: 'https://x/2',
                cutoutStatus: 'done',
              ),
            ],
          ),
        ],
        child: app(),
      ),
    );
    await tester.pump();

    // Exactly the processing item shows the badge.
    expect(find.text('Processing'), findsOneWidget);
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

  testWidgets('long-press → confirm removes the piece', (tester) async {
    final fake = _FakeWardrobeRepository();
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
            ],
          ),
          wardrobeRepositoryProvider.overrideWithValue(fake),
        ],
        child: app(),
      ),
    );
    await tester.pump(); // resolve the future

    await tester.longPress(find.byType(OutfitTile));
    await tester.pump(); // start the dialog transition
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Remove this piece?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pump(); // pop dialog + run delete
    await tester.pump(); // show snackbar

    expect(fake.deleted, ['w1']);
    expect(find.text('Removed from your closet'), findsOneWidget);
  });
}
