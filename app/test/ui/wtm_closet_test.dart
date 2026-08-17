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
import 'package:app/data/models/credits.dart';
import 'package:app/data/models/ai_job.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/credits_repository.dart';
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
/// (pick → upload → REMOVE → confirm → create-at-save → grid refresh).
const _items = [
  WardrobeItem(id: 'w1', title: 'Noir silk blouse', category: 'tops'),
  WardrobeItem(id: 'w2', title: 'Wide trousers', category: 'bottoms'),
  WardrobeItem(id: 'w3', title: 'Trench', category: 'outerwear'),
];

class ErrorWardrobeItemsNotifier extends WardrobeItemsNotifier {
  @override
  Future<List<WardrobeItem>> build() async => throw Exception('network down');
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
  Map<String, Object?>? lastCreate;
  var polls = 0;
  var creates = 0;

  @override
  Future<List<WardrobeItem>> getItems({int? limit, DateTime? before}) async {
    polls++;
    return [..._items, added.copyWith(cutoutStatus: 'done')];
  }

  @override
  Future<WardrobeItem> addItem({
    String? title,
    String? category,
    String? imageUrl,
    String? objectKey,
    String? cutoutJobId,
  }) async {
    expect(objectKey ?? imageUrl, isNotNull);
    creates++;
    lastCreate = {
      'title': title,
      'category': category,
      'cutoutJobId': cutoutJobId,
    };
    return added;
  }

  /// The cloud removal that runs before any garment exists. Terminal already, so
  /// the poller returns it without a loop.
  @override
  Future<AiJob> startCutoutJob(String objectKey) async => const AiJob(
    jobId: 'cut-1',
    status: AiJobStatus.completed,
    jobType: 'cutout_temp',
    outputUrl: 'https://cdn.test/cutout/x.png',
  );

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

  /// No lost capture in a test — the real one is Android-only and self-clearing.
  @override
  Future<Uint8List?> recoverLostCapture() async => null;

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
    Credits? credits,
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
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        if (items != null) wardrobeItemsProvider.overrideWith(items),
        if (repo != null) wardrobeRepositoryProvider.overrideWithValue(repo),
        if (images != null)
          wardrobeImageServiceProvider.overrideWithValue(images),
        if (credits != null)
          creditsProvider.overrideWith((ref) async => credits),
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

  testWidgets('garment detail: heart feeds the Favorites stat', (tester) async {
    await boot(tester, items: () => FakeWardrobeItemsNotifier(_items));
    await tester.tap(find.byType(FabricTile).first);
    await settle(tester);
    expect(find.byType(WtmGarmentDetailScreen), findsOneWidget);

    // Heart it, go back — Favorites stat counts it.
    await tester.tap(
      find.byWidgetPredicate((w) => w is WtmIcon && w.glyph == WtmGlyph.heart),
    );
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
    'add flow money path: pick → remove → confirm → save (one create)',
    (tester) async {
      final repo = FakeWardrobeRepository();
      await boot(
        tester,
        at: AppRoute.wtmClosetAdd,
        repo: repo,
        images: FakeWardrobeImageService(),
      );
      expect(find.byType(WtmAddGarmentScreen), findsOneWidget);

      // The capture stage carries the add-mode choice (Remove background —
      // selected by default — vs the locked AI Enhance) above the pickers.
      expect(find.text('Remove background'), findsOneWidget);
      expect(find.text('AI Enhance'), findsOneWidget);

      await tester.ensureVisible(find.text('Choose from Gallery'));
      await tester.pump();
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pump();

      // The removal runs FIRST. Nothing is asked of the user, and — crucially —
      // nothing is created: the piece the closet eventually receives is built at
      // Save, from metadata the user supplies after seeing the cutout.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);

      // The confirm stage, showing the finished cutout. Asserted on the
      // instruction rather than the heading: WtmPage keeps one ListView
      // across stages, so the earlier ensureVisible leaves a scroll offset
      // that can unmount the top-most child.
      expect(find.text('Name it and confirm the category.'), findsOneWidget);
      expect(repo.creates, 0, reason: 'the closet is untouched until Save');

      // Now the details, on the finished cutout.
      await tester.enterText(find.byType(TextField).first, 'Midnight dress');
      await tester.pump();
      await tester.tap(find.text('Dresses'));
      await tester.pump();
      await tester.ensureVisible(find.text('Save to Closet'));
      await tester.pump();
      await tester.tap(find.text('Save to Closet'));
      await settle(tester);

      // Exactly ONE write, carrying both mandatory fields and the cutout the
      // user just approved. There is no follow-up PATCH any more: the piece is
      // complete the moment it is created, because it is created last.
      expect(repo.creates, 1);
      expect(repo.lastCreate!['title'], 'Midnight dress');
      expect(repo.lastCreate!['category'], 'dresses');
      expect(
        repo.lastCreate!['cutoutJobId'],
        'cut-1',
        reason: 'the finished cutout is adopted, not recomputed',
      );
      expect(repo.lastUpdate, isNull, reason: 'no create-then-complete dance');
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

  // ── mobile QA #3: enhance gating must use the REAL plan, never a stale
  //    loading read (a Pro user was mis-routed to the paywall) ────────────────

  const proMax = Credits(
    balance: 75,
    dailyFreeUsed: 0,
    dailyFreeLimit: 3,
    dailyFreeRemaining: 3,
    totalAvailable: 75,
    tier: 'pro_max',
    hdAllowed: true,
  );

  testWidgets(
    'GATE: Pro Max Enhance opens the credit confirm, NOT the paywall',
    (tester) async {
      await boot(
        tester,
        items: () => FakeWardrobeItemsNotifier(_items),
        credits: proMax,
      );
      await tester.tap(find.byType(FabricTile).first);
      await settle(tester);
      await tester.ensureVisible(find.text('Enhance item'));
      await tester.pump();
      await tester.tap(find.text('Enhance item'));
      await settle(tester);

      // The §18 confirm dialog — not the Atelier Membership screen.
      expect(find.text('AI Enhance'), findsWidgets);
      expect(find.textContaining('credit', findRichText: true), findsWidgets);
      expect(find.text('Membership'), findsNothing);
    },
  );

  testWidgets('GATE: free-tier Enhance still lands on the paywall', (
    tester,
  ) async {
    const free = Credits(
      balance: 0,
      dailyFreeUsed: 0,
      dailyFreeLimit: 3,
      dailyFreeRemaining: 3,
      totalAvailable: 3,
    );
    await boot(
      tester,
      items: () => FakeWardrobeItemsNotifier(_items),
      credits: free,
    );
    await tester.tap(find.byType(FabricTile).first);
    await settle(tester);
    await tester.ensureVisible(find.text('Enhance item'));
    await tester.pump();
    await tester.tap(find.text('Enhance item'));
    await settle(tester);

    // Free tier → the paywall route, no credit confirm.
    expect(find.text('AI Enhance'), findsNothing);
  });
}
