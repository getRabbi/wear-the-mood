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
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 5 UI: the Try-On entry points, the shopping result actions, and the
/// proof that a closet render is untouched by any of it.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({List<Product>? page1, this.detail})
    : page1 = page1 ?? const [];

  final List<Product> page1;
  final ProductDetail? detail;

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
  List<String> images = const ['https://cdn.test/dress.jpg'],
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  brand: 'Studio',
  category: 'dresses',
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  imageUrls: images,
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
        'https://cdn.test/dress.jpg',
      );
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);
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
}
