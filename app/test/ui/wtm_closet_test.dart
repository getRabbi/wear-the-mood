import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/media/media_upload_service.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/wardrobe_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_image_service.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/shared/widgets/loading_shimmer.dart';
import 'package:app/ui/closet/wtm_add_garment_screen.dart';
import 'package:app/ui/closet/wtm_closet_screen.dart';
import 'package:app/ui/closet/wtm_garment_detail_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P3 gate coverage: closet states + the add money path
/// (pick → upload → create → poll cutout → confirm → PATCH → grid refresh).
const _items = [
  WardrobeItem(id: 'w1', title: 'Noir silk blouse', category: 'tops'),
  WardrobeItem(id: 'w2', title: 'Wide trousers', category: 'bottoms'),
  WardrobeItem(id: 'w3', title: 'Trench', category: 'outerwear'),
];

class ErrorWardrobeItemsNotifier extends WardrobeItemsNotifier {
  @override
  Future<List<WardrobeItem>> build() async =>
      throw Exception('network down');
}

/// Scripted repository for the add flow: create returns a processing item,
/// the next closet fetch returns it finished; updateItem records its args.
class FakeWardrobeRepository implements WardrobeRepository {
  FakeWardrobeRepository();

  final added = WardrobeItem(
    id: 'new1',
    category: 'dresses',
    color: 'noir',
    cutoutStatus: 'processing',
  );
  var deleted = <String>[];
  Map<String, Object?>? lastUpdate;
  var polls = 0;

  @override
  Future<List<WardrobeItem>> getItems() async {
    polls++;
    return [..._items, added.copyWith(cutoutStatus: 'done')];
  }

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
  }) async {
    expect(objectKey ?? imageUrl, isNotNull);
    return added;
  }

  @override
  Future<WardrobeItem> updateItem(
    String id, {
    required String? title,
    required String? category,
    required String? color,
    String? subcategory,
  }) async {
    lastUpdate = {
      'id': id,
      'title': title,
      'category': category,
      'color': color,
    };
    return added.copyWith(
      title: title,
      category: category,
      cutoutStatus: 'done',
    );
  }

  @override
  Future<void> deleteItem(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// A real, decodable 1×1 transparent PNG — Image.memory must not choke.
final kTransparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class FakeWardrobeImageService implements WardrobeImageService {
  @override
  Future<Uint8List?> pickAndCompress(ImageSource source) async =>
      kTransparentPng;

  @override
  Future<MediaRef> upload(Uint8List bytes) async =>
      const MediaRef(objectKey: 'wardrobe/u1/new1.jpg');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    WardrobeItemsNotifier Function()? items,
    WardrobeRepository? repo,
    WardrobeImageService? images,
    String at = AppRoute.wtmCloset,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      // Riverpod 3 auto-retries failed providers on a backoff timer, which
      // trips the pending-timer check at teardown — disable in tests.
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        if (items != null) wardrobeItemsProvider.overrideWith(items),
        if (repo != null) wardrobeRepositoryProvider.overrideWithValue(repo),
        if (images != null)
          wardrobeImageServiceProvider.overrideWithValue(images),
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
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return container;
  }

  testWidgets('closet content: grid, stats, category filter', (tester) async {
    await boot(tester, items: () => FakeWardrobeItemsNotifier(_items));
    expect(find.byType(WtmClosetScreen), findsOneWidget);
    expect(find.byType(FabricTile), findsNWidgets(3));
    // Items stat = 3 AND three matched categories also read 3.
    final itemsStat = find.ancestor(
      of: find.text('ITEMS'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: itemsStat.first, matching: find.text('3')),
      findsOneWidget,
    );

    await tester.tap(find.text('Tops'));
    await tester.pump();
    expect(find.byType(FabricTile), findsNWidgets(1));

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.byType(FabricTile), findsNWidgets(3));
  });

  testWidgets('closet loading state shimmers on swatches', (tester) async {
    await boot(tester, items: LoadingWardrobeItemsNotifier.new);
    expect(find.byType(LoadingShimmer), findsWidgets);
  });

  testWidgets('closet error state offers retry', (tester) async {
    await boot(tester, items: ErrorWardrobeItemsNotifier.new);
    expect(find.byType(WtmErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('closet empty state invites the first add', (tester) async {
    await boot(tester, items: () => FakeWardrobeItemsNotifier(const []));
    expect(find.byType(WtmEmptyState), findsOneWidget);
    await tester.tap(find.text('Add your first piece'));
    await settle(tester);
    expect(find.byType(WtmAddGarmentScreen), findsOneWidget);
  });

  testWidgets('garment detail: heart feeds the Favorites stat', (
    tester,
  ) async {
    await boot(tester, items: () => FakeWardrobeItemsNotifier(_items));
    await tester.tap(find.byType(FabricTile).first);
    await settle(tester);
    expect(find.byType(WtmGarmentDetailScreen), findsOneWidget);

    // Heart it, go back — Favorites stat counts it.
    await tester.tap(find.byWidgetPredicate(
      (w) => w is WtmIcon && w.glyph == WtmGlyph.heart,
    ));
    await tester.pump();
    await tester.tap(find.byType(WtmIconButton).first); // back
    await settle(tester);
    final stat = find.ancestor(
      of: find.text('FAVORITES'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: stat.first, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'add flow money path: pick → process → confirm → save (color preserved)',
    (tester) async {
      final repo = FakeWardrobeRepository();
      await boot(
        tester,
        at: AppRoute.wtmClosetAdd,
        repo: repo,
        images: FakeWardrobeImageService(),
      );
      expect(find.byType(WtmAddGarmentScreen), findsOneWidget);

      await tester.tap(find.text('Choose from Gallery'));
      // pick resolves → processing → first poll at 350ms returns 'done'.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);

      // Confirm stage: tagger's category (dresses) is preselected.
      expect(find.text('Looking sharp'), findsOneWidget);
      expect(repo.polls, greaterThan(0));

      await tester.enterText(
          find.byType(TextField).first, 'Midnight dress');
      await tester.tap(find.text('Save to Closet'));
      await settle(tester);

      expect(repo.lastUpdate, isNotNull);
      expect(repo.lastUpdate!['id'], 'new1');
      expect(repo.lastUpdate!['title'], 'Midnight dress');
      expect(repo.lastUpdate!['category'], 'dresses');
      // The tagger's color survives the PATCH (null would clear it).
      expect(repo.lastUpdate!['color'], 'noir');
      // Saved → back on the closet, which now holds the new piece.
      expect(find.byType(WtmClosetScreen), findsOneWidget);
      expect(find.byType(FabricTile), findsNWidgets(4));
    },
  );

  testWidgets('garment delete: confirm → DELETE → back on closet', (
    tester,
  ) async {
    final repo = FakeWardrobeRepository();
    await boot(
      tester,
      repo: repo,
      items: () => FakeWardrobeItemsNotifier(_items),
    );
    await tester.tap(find.byType(FabricTile).first);
    await settle(tester);
    await tester.ensureVisible(find.text('Delete'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await settle(tester, 400);
    await tester.tap(find.text('Delete').last); // dialog confirm
    await settle(tester);

    expect(repo.deleted, isNotEmpty);
    expect(find.byType(WtmClosetScreen), findsOneWidget);
  });
}
