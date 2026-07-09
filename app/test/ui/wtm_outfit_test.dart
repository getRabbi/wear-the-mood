import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/outfit_repository.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/ui/outfits/wtm_outfit_composer.dart';
import 'package:app/ui/outfits/wtm_outfit_detail_screen.dart';
import 'package:app/ui/outfits/wtm_outfits_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P5 gate coverage: the Outfit Maker on the real outfit backend — saved grid,
/// composer create, delete, edit pre-fill, and the "Try It On" → Step 2 handoff.

class _FakeOutfitRepo implements OutfitRepository {
  Map<String, Object?>? created;
  Map<String, Object?>? updated;
  final deleted = <String>[];

  @override
  Future<Outfit> createOutfit({
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async {
    created = {'name': name, 'itemIds': itemIds};
    return Outfit(id: 'o-new', name: name, itemIds: itemIds);
  }

  @override
  Future<Outfit> updateOutfit(
    String id, {
    String? name,
    required List<String> itemIds,
    String? coverImageUrl,
  }) async {
    updated = {'id': id, 'name': name, 'itemIds': itemIds};
    return Outfit(id: id, name: name, itemIds: itemIds);
  }

  @override
  Future<void> deleteOutfit(String id) async => deleted.add(id);

  @override
  Future<List<Outfit>> getOutfits() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _pieces = [
  WardrobeItem(
      id: 'w1', title: 'Noir blouse', category: 'tops',
      imageUrl: 'https://cdn.test/w1.png'),
  WardrobeItem(
      id: 'w2', title: 'Wide trousers', category: 'bottoms',
      imageUrl: 'https://cdn.test/w2.png'),
];

const _outfit =
    Outfit(id: 'o1', name: 'Evening Layers', itemIds: ['w1', 'w2']);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    final target = finder.first;
    final rect = tester.getRect(target);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (rect.center.dy < 0 || rect.center.dy > screen.height - 100) {
      await tester.ensureVisible(target);
      await tester.pump();
    }
    await tester.tap(target);
    await settle(tester);
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    List<Outfit> outfits = const [],
    List<WardrobeItem> items = _pieces,
    _FakeOutfitRepo? repo,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(items),
        ),
        outfitsProvider.overrideWith((ref) => outfits),
        if (repo != null)
          outfitRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmOutfits);
    await settle(tester);
    return container;
  }

  testWidgets('saved grid renders and a card opens the detail', (tester) async {
    final container = await boot(tester, outfits: const [_outfit]);
    expect(find.byType(WtmOutfitsScreen), findsOneWidget);
    expect(find.text('Evening Layers'), findsOneWidget);

    await tapAndSettle(tester, find.text('Evening Layers'));
    expect(find.byType(WtmOutfitDetailScreen), findsOneWidget);
    // Real backend id flowed through the route extra.
    expect(container.read(goRouterProvider).state.matchedLocation,
        AppRoute.wtmOutfitDetail);
  });

  testWidgets('GATE: outfit detail Try It On pre-fills Step 2', (tester) async {
    final container = await boot(tester, outfits: const [_outfit]);
    container.read(goRouterProvider).push(
          AppRoute.wtmOutfitDetail,
          extra: _outfit,
        );
    await settle(tester);
    expect(find.byType(WtmOutfitDetailScreen), findsOneWidget);

    await tapAndSettle(tester, find.text('Try It On'));
    expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
    expect(container.read(wtmMirrorFlowProvider).layers.length, 2);
  });

  testWidgets('composer picker fills the active slot', (tester) async {
    final container = await boot(tester);
    // Default active slot is Top (0); tap a closet piece to drop it in.
    await tapAndSettle(tester, find.byType(FabricTile).first);
    expect(container.read(wtmOutfitComposerProvider).slots[0], 'w1');
  });

  testWidgets('composer save creates an outfit from the filled slots', (
    tester,
  ) async {
    final repo = _FakeOutfitRepo();
    final container = await boot(tester, repo: repo);
    container.read(wtmOutfitComposerProvider.notifier).setSlot(0, 'w1');
    container.read(wtmOutfitComposerProvider.notifier).setSlot(1, 'w2');
    await settle(tester);

    await tapAndSettle(tester, find.text('Save Outfit'));
    expect(repo.created, isNotNull);
    expect(repo.created!['itemIds'], ['w1', 'w2']);
    // Draft resets after a successful save.
    expect(container.read(wtmOutfitComposerProvider).isEmpty, isTrue);
  });

  testWidgets('composer save with no pieces warns instead of creating', (
    tester,
  ) async {
    final repo = _FakeOutfitRepo();
    await boot(tester, repo: repo);
    await tapAndSettle(tester, find.text('Save Outfit'));
    expect(repo.created, isNull);
    expect(find.text('Pick a piece for at least one slot first.'),
        findsOneWidget);
  });

  testWidgets('outfit Edit pre-fills the composer draft', (tester) async {
    final container = await boot(tester, outfits: const [_outfit]);
    container.read(goRouterProvider).push(
          AppRoute.wtmOutfitDetail,
          extra: _outfit,
        );
    await settle(tester);

    await tapAndSettle(tester, find.text('Edit'));
    final draft = container.read(wtmOutfitComposerProvider);
    expect(draft.editingId, 'o1');
    expect(draft.itemIds, ['w1', 'w2']);
  });

  testWidgets('outfit Delete confirms then removes', (tester) async {
    final repo = _FakeOutfitRepo();
    final container = await boot(tester, outfits: const [_outfit], repo: repo);
    container.read(goRouterProvider).push(
          AppRoute.wtmOutfitDetail,
          extra: _outfit,
        );
    await settle(tester);

    await tapAndSettle(tester, find.text('Delete'));
    await tapAndSettle(tester, find.text('Delete').last); // dialog confirm
    expect(repo.deleted, contains('o1'));
  });
}
