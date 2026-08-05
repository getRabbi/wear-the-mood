import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/tryon_job.dart' as job;
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/discover/application/shopping_tryon.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/tryon/models/studio_models.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_preselect.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_result.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/data/models/tryon_source.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/collections/local_collections.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 5 UI: the Try-On entry points, the shopping result actions, and the
/// proof that a closet render is untouched by any of it.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({List<Product>? page1, this.detail, this.clickError})
    : page1 = page1 ?? const [];

  final List<Product> page1;
  final ProductDetail? detail;
  final Object? clickError;

  final clickKeys = <String>[];
  final placements = <String?>[];
  final interactions = <String>[];

  @override
  Future<ProductPageResult> products({
    String? cursor,
    int? limit,
    String? country,
    String? currency,
    String? category,
    String? subcategory,
    String? audience,
    List<String> colors = const [],
    List<String> sizes = const [],
    List<String> brands = const [],
    int? minPriceMinor,
    int? maxPriceMinor,
    bool tryOnReady = false,
    bool discounted = false,
    String? query,
    CancelToken? cancelToken,
  }) async => ProductPageResult(
    page: ProductPage(items: cursor != null ? const [] : page1),
    raw: const {},
  );

  @override
  Future<ProductDetail> product(String productId) async =>
      detail ?? ProductDetail(product: page1.first, servable: true);

  @override
  Future<List<Product>> similar(String productId, {int? limit}) async =>
      const [];

  @override
  Future<AffiliateClick> click(
    String productId, {
    required String idempotencyKey,
    String? feedPlacement,
    String? storyId,
    String? campaignId,
    String? trackingToken,
  }) async {
    clickKeys.add(idempotencyKey);
    placements.add(feedPlacement);
    if (clickError != null) throw clickError!;
    return const AffiliateClick(
      clickId: 'c1',
      url: 'https://shop.example.test/p/1',
      merchant: MerchantSummary(id: 'm1', name: 'Studio Label'),
      // The server's answer, and on this path it should be true: the render
      // the user is looking at IS the try-on.
      tryOnCompleted: true,
    );
  }

  @override
  Future<List<SavedProduct>> saved() async => const [];

  @override
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async {}

  @override
  Future<void> unsave(String productId) async {}

  @override
  Future<void> recordInteraction({
    required String eventType,
    String? productId,
    String? merchantId,
    String? feedPlacement,
    String? storyId,
    String? trackingToken,
    String? clientEventId,
  }) async => interactions.add('$eventType:${productId ?? ''}');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeLauncher implements LinkLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return true;
  }
}

class _FakeGiveaway implements GiveawayRepository {
  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOffers implements OffersRepository {
  @override
  Future<List<Offer>> getToday() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async =>
      const [];
  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeStore implements DiscoverLocalStore {
  @override
  Future<Map<String, int>> seenStoryVersions() async => const {};
  @override
  Future<List<String>> recentSearches() async => const [];
  @override
  Future<(String?, String?, int)> shoppingScope() async => (null, null, 0);
  @override
  Future<void> setShoppingScope(String? c, String? cur, int v) async {}
  @override
  Future<void> addRecentlyViewedProduct(String productId) async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NoCache implements DiscoverFeedCache {
  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key) async => null;
  @override
  Future<void> write(DiscoverFeedCacheKey key, Map<String, dynamic> r) async {}
  @override
  Future<void> clear() async {}
}

Product _product({
  String id = 'p1',
  TryOnStatus tryOn = TryOnStatus.ready,
  List<String>? images,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  brand: 'Studio',
  category: 'dresses',
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  imageUrls: images ?? ['https://cdn.test/$id.jpg'],
  tryOnStatus: tryOn,
  trackingToken: 'p:$id',
);

const _doneJob = job.TryOnJob(
  jobId: 'j1',
  status: job.TryOnStatus.done,
  resultImageUrl: 'https://cdn.test/render.jpg',
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required _FakeDiscover discover,
    _FakeLauncher? launcher,
    String at = AppRoute.wtmDiscover,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => {FeatureFlags.discover, FeatureFlags.shopping},
        ),
        discoverRepositoryProvider.overrideWithValue(discover),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier([])),
        if (launcher != null) linkLauncherProvider.overrideWithValue(launcher),
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

  /// Puts the app on a finished render, the way the generating screen does.
  void completeRender(ProviderContainer container) {
    container.read(tryOnControllerProvider.notifier).state =
        const TryOnState.success(_doneJob);
  }

  /// Seeds a finished SHOPPING render and lands on the result.
  ///
  /// `go`, not `push`: the mirror steps live in the Home branch and the product
  /// routes in the Discover branch, and stacking both branches' routes in one
  /// test navigator is a go_router shell detail rather than anything about
  /// Phase 5. What matters is the state the result screen reads.
  Future<void> shoppingResult(
    WidgetTester tester,
    ProviderContainer container, {
    String productId = 'p1',
  }) async {
    container
        .read(shoppingTryOnSourceProvider.notifier)
        .set(
          ShoppingTryOnSource(
            productId: productId,
            merchantId: 'm1',
            title: 'Black silk dress',
            imageUrl: 'https://cdn.test/dress.jpg',
            trackingToken: 'p:$productId',
            feedPlacement: 'feed_grid',
          ),
        );
    container.read(wtmMirrorFlowProvider.notifier).setLayers([
      TryOnLayer.fromSource(imageUrl: 'https://cdn.test/dress.jpg', zIndex: 0),
    ]);
    completeRender(container);
    container.read(goRouterProvider).go(AppRoute.wtmMirrorResult);
    await settle(tester);
  }

  /// Taps the pushed page's own back glyph. `tester.pageBack()` looks for a
  /// Material BackButton and WtmPage draws its own.
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(
      find
          .byWidgetPredicate((w) => w is WtmIcon && w.glyph == WtmGlyph.back)
          .first,
    );
    await settle(tester);
  }

  // The card's pill renders its label uppercased; Product Details' button
  // does not.
  final tryOnBadge = find.descendant(
    of: find.byType(WtmProductCard),
    matching: find.text('TRY ON'),
  );

  group('entry points', () {
    testWidgets('the card badge sends the product into the mirror flow', (
      tester,
    ) async {
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );

      expect(tryOnBadge, findsOneWidget);
      await tester.tap(tryOnBadge);
      await settle(tester);

      // The existing pipeline's own garment step, not a parallel one.
      expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
      // Seeded through the SAME door the closet handoff uses, and consumed.
      expect(container.read(tryOnPreselectProvider), isNull);
      expect(container.read(wtmMirrorFlowProvider).layers, hasLength(1));
      expect(
        container.read(wtmMirrorFlowProvider).layers.single.imageUrl,
        'https://cdn.test/p1.jpg',
      );
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);
    });

    testWidgets('a second product replaces the first, never stacks on it', (
      tester,
    ) async {
      // The sequence that matters: Details(A) → Try On → back → Details(B) →
      // Try On. Step 2 does not necessarily re-mount in between, so relying on
      // its consume-on-mount would leave A in the stack and render both.
      final container = await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(id: 'pA'),
            _product(id: 'pB'),
          ],
          detail: ProductDetail(
            product: _product(id: 'pA'),
            servable: true,
            shoppable: true,
          ),
        ),
      );

      await tester.tap(tryOnBadge.first);
      await settle(tester);
      expect(container.read(wtmMirrorFlowProvider).layers, hasLength(1));
      expect(
        container.read(activeShoppingTryOnSourceProvider)!.productId,
        'pA',
      );

      await goBack(tester);
      // Product B's badge — the second card in the feed.
      await tester.tap(tryOnBadge.at(1));
      await settle(tester);

      final layers = container.read(wtmMirrorFlowProvider).layers;
      expect(layers, hasLength(1), reason: 'A must not still be in the stack');
      expect(layers.single.imageUrl, 'https://cdn.test/pB.jpg');
      expect(
        container.read(activeShoppingTryOnSourceProvider)!.productId,
        'pB',
      );
    });

    testWidgets('a closet try-on afterwards drops the product entirely', (
      tester,
    ) async {
      // A stale product riding along on somebody's closet render would offer
      // to buy something they never tried on.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );
      await tester.tap(tryOnBadge);
      await settle(tester);
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);

      // The closet/outfit/stylist handoff, unchanged: it seeds the preselect
      // and Step 2 consumes it — which is exactly what happens here, since
      // Step 2 is on screen and listening.
      container.read(tryOnPreselectProvider.notifier).setItems(const [
        WardrobeItem(id: 'w1', imageUrl: 'https://cdn.test/my-jacket.jpg'),
      ]);
      await settle(tester);
      expect(
        container.read(tryOnPreselectProvider),
        isNull,
        reason: 'Step 2 consumes and clears the queue',
      );

      final layers = container.read(wtmMirrorFlowProvider).layers;
      expect(layers.map((l) => l.imageUrl), ['https://cdn.test/my-jacket.jpg']);
      expect(layers.single.wardrobeItemId, 'w1');
      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
    });

    testWidgets('the closet handoff still works through the preselect door', (
      tester,
    ) async {
      // The regression guard for task 1: nothing about multi-garment or
      // full-look seeding changed.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );
      final seeded = container
          .read(tryOnPreselectProvider.notifier)
          .setItems(const [
            WardrobeItem(id: 'w1', imageUrl: 'https://cdn.test/a.jpg'),
            WardrobeItem(id: 'w2', imageUrl: 'https://cdn.test/b.jpg'),
            WardrobeItem(id: 'w3', imageUrl: 'https://cdn.test/c.jpg'),
          ]);

      expect(seeded, isTrue);
      expect(container.read(tryOnPreselectProvider), hasLength(3));
      // Every piece keeps its wardrobe id — the full-look stack is intact.
      expect(
        container.read(tryOnPreselectProvider)!.map((l) => l.wardrobeItemId),
        ['w1', 'w2', 'w3'],
      );
    });

    testWidgets('a product not verified compatible shows no badge at all', (
      tester,
    ) async {
      // `pending` is not ready — a product is never labelled Try-On Ready
      // until compatibility has actually passed (§35).
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product(tryOn: TryOnStatus.pending)]),
      );
      expect(tryOnBadge, findsNothing);
    });

    testWidgets('Product Details offers Try On beside Shop at Store', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product()],
          detail: ProductDetail(
            product: _product(),
            servable: true,
            shoppable: true,
          ),
        ),
      );
      await tester.tap(find.byType(WtmProductCard).first);
      await settle(tester);

      expect(find.widgetWithText(GhostButton, 'Try On'), findsOneWidget);
      expect(find.widgetWithText(GradientCta, 'Shop at Store'), findsOneWidget);
      // Save has not disappeared — it keeps the header heart.
      expect(find.widgetWithText(GhostButton, 'Save'), findsNothing);
    });

    testWidgets('a non-try-on product keeps the Save + Shop pairing', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product(tryOn: TryOnStatus.unsupported)],
          detail: ProductDetail(
            product: _product(tryOn: TryOnStatus.unsupported),
            servable: true,
            shoppable: true,
          ),
        ),
      );
      await tester.tap(find.byType(WtmProductCard).first);
      await settle(tester);

      expect(find.widgetWithText(GhostButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(GhostButton, 'Try On'), findsNothing);
    });

    testWidgets('a sold-out product cannot be tried on', (tester) async {
      // Paying credits to render something nobody can buy would be the worst
      // possible use of them.
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product()],
          detail: ProductDetail(
            product: _product(),
            servable: false,
            shoppable: false,
          ),
        ),
      );
      await tester.tap(find.byType(WtmProductCard).first);
      await settle(tester);

      expect(find.widgetWithText(GhostButton, 'Try On'), findsNothing);
      expect(find.widgetWithText(GhostButton, 'Save'), findsOneWidget);
    });

    testWidgets('a product with no usable image warns instead of dead-ending', (
      tester,
    ) async {
      // The server suppresses imageless products, so the badge showing here is
      // defence in depth — but the tap must still explain itself rather than
      // opening a flow that would fail with nothing to render.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product(images: const [])]),
      );
      await tester.tap(tryOnBadge);
      await settle(tester);

      expect(
        find.text("This piece isn't ready for try-on yet."),
        findsOneWidget,
      );
      expect(find.byType(WtmMirrorStep2Screen), findsNothing);
      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
    });
  });

  group('the shopping result', () {
    testWidgets('leads with Shop at Store and offers the way back', (
      tester,
    ) async {
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );
      await shoppingResult(tester, container);

      expect(find.byType(WtmMirrorResultScreen), findsOneWidget);
      expect(find.widgetWithText(GradientCta, 'Shop at Store'), findsOneWidget);
      expect(find.widgetWithText(GhostButton, 'View Product'), findsOneWidget);
      // Save Look is still there, one row down.
      expect(find.widgetWithText(GhostButton, 'Save Look'), findsOneWidget);
    });

    testWidgets('a closet render is completely unchanged', (tester) async {
      // The regression that matters most in this phase: the overwhelmingly
      // common path must look exactly as it did before.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );
      container.read(wtmMirrorFlowProvider.notifier).setLayers([
        TryOnLayer.fromSource(
          imageUrl: 'https://cdn.test/my-own-jacket.jpg',
          wardrobeItemId: 'w1',
          zIndex: 0,
        ),
      ]);
      completeRender(container);

      container.read(goRouterProvider).go(AppRoute.wtmMirrorResult);
      await settle(tester);

      expect(find.widgetWithText(GradientCta, 'Save Look'), findsOneWidget);
      expect(find.widgetWithText(GradientCta, 'Shop at Store'), findsNothing);
      expect(find.widgetWithText(GhostButton, 'View Product'), findsNothing);
    });

    testWidgets('Shop at Store opens only the URL the backend returned', (
      tester,
    ) async {
      final repo = _FakeDiscover(page1: [_product()]);
      final launcher = _FakeLauncher();
      final container = await boot(tester, discover: repo, launcher: launcher);
      await shoppingResult(tester, container);

      await tester.tap(find.widgetWithText(GradientCta, 'Shop at Store'));
      await settle(tester);

      expect(launcher.opened, ['https://shop.example.test/p/1']);
      // Distinct from a click straight off a card — the try-on-to-shop rate
      // cannot be measured if both look the same.
      expect(repo.placements, ['tryon_result']);
      expect(repo.clickKeys, hasLength(1));
    });

    testWidgets('View Product returns to the product that was tried on', (
      tester,
    ) async {
      final container = await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product()],
          detail: ProductDetail(
            product: _product(),
            servable: true,
            shoppable: true,
          ),
        ),
      );
      await shoppingResult(tester, container);

      await tester.tap(find.widgetWithText(GhostButton, 'View Product'));
      await settle(tester);

      final screen = tester.widget<WtmProductDetailsScreen>(
        find.byType(WtmProductDetailsScreen),
      );
      expect(screen.productId, 'p1');
      expect(screen.placement, 'tryon_result');
    });
  });

  group('restoration after a restart', _restorationTests);
}

/// Phase 5.1: a completed shopping result reopened from Saved Looks, after the
/// process that made it is gone. The only thing left on device is the job id.
void _restorationTests() {
  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> bootLooks(
    WidgetTester tester, {
    required _RestoreTryOn tryon,
    _FakeDiscover? discover,
    _FakeLauncher? launcher,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => {FeatureFlags.discover, FeatureFlags.shopping},
        ),
        tryOnRepositoryProvider.overrideWithValue(tryon),
        discoverRepositoryProvider.overrideWithValue(
          discover ?? _FakeDiscover(page1: [_product()]),
        ),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier([])),
        if (launcher != null) linkLauncherProvider.overrideWithValue(launcher),
      ],
    );
    addTearDown(container.dispose);
    // A saved look is everything a restarted app has: an id and an image.
    container
        .read(savedLookRecordsProvider.notifier)
        .add(
          SavedLook(
            id: 'job-1',
            imageUrl: 'https://cdn.test/render.jpg',
            createdAt: DateTime(2026, 8, 1),
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmLooks);
    await settle(tester);
    // The grid tile, precisely — the screen has other gesture detectors.
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    await settle(tester);
    return container;
  }

  testWidgets('a shopping look comes back with its product actions', (
    tester,
  ) async {
    // Nothing in memory says this render was of a product — only the job does.
    final tryon = _RestoreTryOn(
      source: const TryOnSource(
        productId: 'p1',
        merchantId: 'm1',
        placement: 'feed_grid',
      ),
    );
    await bootLooks(tester, tryon: tryon);

    expect(tryon.jobRequests, ['job-1']);
    expect(find.widgetWithText(GoldPill, 'VIEW PRODUCT'), findsOneWidget);
    expect(find.widgetWithText(GoldPill, 'SHOP AT STORE'), findsOneWidget);
  });

  testWidgets('an ordinary closet look is untouched', (tester) async {
    // Backward compatibility: every look saved before this feature existed.
    await bootLooks(tester, tryon: _RestoreTryOn());

    expect(find.widgetWithText(GoldPill, 'VIEW PRODUCT'), findsNothing);
    expect(find.widgetWithText(GoldPill, 'SHOP AT STORE'), findsNothing);
    // And it still opens, with the action it always had.
    expect(find.widgetWithText(GoldPill, 'SHARE LOOK'), findsOneWidget);
  });

  testWidgets('a job that cannot be fetched degrades to a plain look', (
    tester,
  ) async {
    // A history tile must never fail to open because a back-link could not be
    // resolved.
    await bootLooks(tester, tryon: _RestoreTryOn(fails: true));

    expect(find.widgetWithText(GoldPill, 'SHOP AT STORE'), findsNothing);
    expect(find.widgetWithText(GoldPill, 'SHARE LOOK'), findsOneWidget);
  });

  testWidgets('Shop from a restored look uses the live click flow', (
    tester,
  ) async {
    // Nothing is restored from cache: the destination is produced now, by the
    // Phase 4 endpoint, and validated server-side.
    final discover = _FakeDiscover(page1: [_product()]);
    final launcher = _FakeLauncher();
    await bootLooks(
      tester,
      tryon: _RestoreTryOn(
        source: const TryOnSource(productId: 'p1', merchantId: 'm1'),
      ),
      discover: discover,
      launcher: launcher,
    );

    await tester.tap(find.widgetWithText(GoldPill, 'SHOP AT STORE'));
    await settle(tester);

    expect(launcher.opened, ['https://shop.example.test/p/1']);
    expect(discover.placements, ['tryon_result']);
  });

  testWidgets('a withdrawn product shows the unavailable state, not a link', (
    tester,
  ) async {
    final discover = _FakeDiscover(
      page1: [_product()],
      clickError: const ApiException(
        code: ApiErrorCode.notFound,
        message: 'gone',
      ),
    );
    final launcher = _FakeLauncher();
    await bootLooks(
      tester,
      tryon: _RestoreTryOn(
        source: const TryOnSource(productId: 'p1', merchantId: 'm1'),
      ),
      discover: discover,
      launcher: launcher,
    );

    await tester.tap(find.widgetWithText(GoldPill, 'SHOP AT STORE'));
    await settle(tester);

    expect(find.text('No longer available'), findsOneWidget);
    expect(launcher.opened, isEmpty);
  });
}

/// A try-on repository that only has to answer "what was this job of?".
class _RestoreTryOn implements TryOnRepository {
  _RestoreTryOn({this.source, this.fails = false});

  final TryOnSource? source;
  final bool fails;
  final jobRequests = <String>[];

  @override
  Future<job.TryOnJob> getJob(String jobId) async {
    jobRequests.add(jobId);
    if (fails) throw Exception('offline');
    return job.TryOnJob(
      jobId: jobId,
      status: job.TryOnStatus.done,
      resultImageUrl: 'https://cdn.test/render.jpg',
      source: source,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}
