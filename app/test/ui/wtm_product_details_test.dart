import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:app/app.dart';
import 'package:app/core/analytics/analytics.dart';
import 'package:app/core/analytics/analytics_events.dart';
import 'package:app/core/analytics/analytics_provider.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/core/utils/link_launcher.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_discover_artwork.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 4: Product Details, revalidation, the tracked affiliate click, saved
/// synchronization and scroll preservation.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({
    List<Product>? page1,
    this.detail,
    this.similarItems = const [],
    this.detailFails = false,
    this.clickError,
    this.clickResult,
  }) : page1 = page1 ?? const [];

  final List<Product> page1;
  final ProductDetail? detail;
  final List<Product> similarItems;
  final bool detailFails;

  /// Thrown by [click] when set — the two failure shapes Product Details has
  /// to tell apart.
  final Object? clickError;
  final AffiliateClick? clickResult;

  final savedCalls = <String>[];
  final unsavedCalls = <String>[];
  final interactions = <String>[];

  /// Every Idempotency-Key a click was attempted with, in order. The whole
  /// point of the key is that a retry reuses it.
  final clickKeys = <String>[];
  int detailRequests = 0;

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
  Future<ProductDetail> product(String productId) async {
    detailRequests++;
    if (detailFails) {
      throw const ApiException(code: ApiErrorCode.network, message: 'down');
    }
    return detail ?? ProductDetail(product: page1.first, servable: true);
  }

  @override
  Future<List<Product>> similar(String productId, {int? limit}) async =>
      similarItems;

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
    if (clickError != null) throw clickError!;
    return clickResult ?? _click;
  }

  @override
  Future<List<SavedProduct>> saved() async => const [];

  @override
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async => savedCalls.add(productId);

  @override
  Future<void> unsave(String productId) async => unsavedCalls.add(productId);

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

/// Records the URL handed to the platform browser — and proves the app never
/// builds one itself.
class _FakeLauncher implements LinkLauncher {
  _FakeLauncher({this.succeeds = true});

  final bool succeeds;
  final opened = <String>[];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return succeeds;
  }
}

class _RecordingAnalytics implements Analytics {
  final events = <String>[];
  final props = <String, Map<String, Object>?>{};

  @override
  Future<void> track(String event, {Map<String, Object>? properties}) async {
    events.add(event);
    props[event] = properties;
  }

  @override
  Future<void> identify(String userId) async {}

  @override
  Future<void> reset() async {}
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
  final viewed = <String>[];

  @override
  Future<Map<String, int>> seenStoryVersions() async => const {};
  @override
  Future<List<String>> recentSearches() async => const [];
  @override
  Future<(String?, String?, int)> shoppingScope() async => (null, null, 0);
  @override
  Future<void> setShoppingScope(String? c, String? cur, int v) async {}
  @override
  Future<void> addRecentlyViewedProduct(String productId) async =>
      viewed.add(productId);
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
  String title = 'Black silk dress',
  int priceMinor = 349900,
  int? originalMinor,
  bool saved = false,
  StockStatus stock = StockStatus.inStock,
  TryOnStatus tryOn = TryOnStatus.unsupported,
  // No image by default: a widget test must not reach the network, and the
  // gallery's own empty treatment is what renders instead.
  List<String> images = const [],
  List<String> sizes = const [],
  List<ProductVariant> variants = const [],
  String? description,
  DateTime? lastSynced,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: title,
  brand: 'Studio',
  category: 'dresses',
  description: description,
  price: Money(amountMinor: priceMinor, currency: 'BDT'),
  originalPrice: originalMinor == null
      ? null
      : Money(amountMinor: originalMinor, currency: 'BDT'),
  imageUrls: images,
  sizes: sizes,
  variants: variants,
  saved: saved,
  stockStatus: stock,
  tryOnStatus: tryOn,
  trackingToken: 'p:$id',
  lastSyncedAt: lastSynced,
);

const _click = AffiliateClick(
  clickId: 'c1',
  url: 'https://shop.example.test/p/sku-123?aff=tag',
  merchant: MerchantSummary(id: 'm1', name: 'Studio Label'),
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
    _RecordingAnalytics? analytics,
    _FakeStore? store,
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
        discoverLocalStoreProvider.overrideWithValue(store ?? _FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier([])),
        if (launcher != null) linkLauncherProvider.overrideWithValue(launcher),
        if (analytics != null) analyticsProvider.overrideWithValue(analytics),
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

  /// Opens Details the way a user does — by tapping a card in the feed — so
  /// the navigation itself is under test, not just the screen.
  ///
  /// `hitTestable` picks a card actually on screen: after a scroll the first
  /// card in the tree may be above the viewport, and tapping it would be
  /// testing the finder rather than the app.
  Future<void> openFromFeed(WidgetTester tester) async {
    await tester.tap(find.byType(WtmProductCard).hitTestable().first);
    await settle(tester);
  }

  /// Drags Product Details up so a section below the fold is built. The page is
  /// a lazy list, so an assertion on a far-down section fails on a widget that
  /// was simply never created.
  Future<void> scrollDetails(WidgetTester tester) async {
    await tester.drag(
      find
          .descendant(
            of: find.byType(WtmProductDetailsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -1200),
    );
    await settle(tester);
  }

  final shopButton = find.widgetWithText(GradientCta, 'Shop at Store');

  /// Taps Product Details' own back control. `tester.pageBack()` looks for a
  /// Material BackButton, and WtmPage draws its own glyph.
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(WtmProductDetailsScreen),
        matching: find.byWidgetPredicate(
          (w) => w is WtmIcon && w.glyph == WtmGlyph.back,
        ),
      ),
    );
    await settle(tester);
  }

  double feedOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  group('the gallery', () {
    testWidgets('an imageless product gets the drawn garment, not a blank', (
      tester,
    ) async {
      // The hero used one flat aurora panel for loading, missing and failed
      // alike, so against a catalog whose image host does not resolve it was a
      // full-bleed blank violet rectangle.
      await boot(tester, discover: _FakeDiscover(page1: [_product()]));
      await openFromFeed(tester);

      expect(
        find.descendant(
          of: find.byType(WtmProductDetailsScreen),
          matching: find.byKey(wtmArtworkFallbackKey),
        ),
        findsWidgets,
      );
    });

    testWidgets('a product WITH an image asks for the real one', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(images: const ['https://cdn.test/a.jpg']),
          ],
        ),
      );
      await openFromFeed(tester);

      final artwork = tester
          .widgetList<WtmDiscoverArtwork>(
            find.descendant(
              of: find.byType(WtmProductDetailsScreen),
              matching: find.byType(WtmDiscoverArtwork),
            ),
          )
          .toList();
      expect(artwork, isNotEmpty);
      expect(artwork.any((a) => a.url == 'https://cdn.test/a.jpg'), isTrue);
    });
  });

  group('navigation', () {
    testWidgets('tapping a product card opens Product Details for it', (
      tester,
    ) async {
      await boot(tester, discover: _FakeDiscover(page1: [_product()]));
      await openFromFeed(tester);

      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
      final screen = tester.widget<WtmProductDetailsScreen>(
        find.byType(WtmProductDetailsScreen),
      );
      expect(screen.productId, 'p1');
      // The card's copy rides along so the screen is never blank on arrival.
      expect(screen.initial?.id, 'p1');
      expect(screen.placement, 'feed_grid');
    });

    testWidgets('Discover keeps its scroll position behind Product Details', (
      tester,
    ) async {
      // Returning to a feed that has jumped back to the top is the failure
      // §33.2 names; `push` is what prevents it.
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [for (var i = 0; i < 12; i++) _product(id: 'p$i')],
        ),
      );

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(tester);
      final scrolled = feedOffset(tester);
      expect(scrolled, greaterThan(0));

      await openFromFeed(tester);
      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);

      await goBack(tester);

      expect(find.byType(WtmProductDetailsScreen), findsNothing);
      expect(feedOffset(tester), scrolled);
    });
  });

  group('revalidation', () {
    testWidgets('the fresh price replaces the one the card was showing', (
      tester,
    ) async {
      // The feed's copy can be minutes old, and from the offline cache days
      // old. What the user acts on comes from the fresh response (§12, §35).
      final stale = _product(priceMinor: 349900);
      final repo = _FakeDiscover(
        page1: [stale],
        detail: ProductDetail(
          product: _product(priceMinor: 199900),
          servable: true,
          shoppable: true,
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      expect(repo.detailRequests, 1);
      // Scoped to the screen, because the feed underneath still holds the card
      // that was tapped — and it is the SCREEN that must show the new price.
      final onScreen = find.descendant(
        of: find.byType(WtmProductDetailsScreen),
        matching: find.textContaining('1,999'),
      );
      expect(onScreen, findsWidgets);
      expect(
        find.descendant(
          of: find.byType(WtmProductDetailsScreen),
          matching: find.textContaining('3,499'),
        ),
        findsNothing,
      );
    });

    testWidgets('a stale source is qualified rather than stated flatly', (
      tester,
    ) async {
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(
            lastSynced: DateTime.now().subtract(const Duration(days: 3)),
          ),
          servable: true,
          stale: true,
          shoppable: true,
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      expect(find.textContaining('last confirmed'), findsOneWidget);
    });

    testWidgets('variant availability is shown per size and colour', (
      tester,
    ) async {
      // "Has size M" and "size M is in stock in black" are different claims.
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(
            variants: const [
              ProductVariant(id: 'v1', size: 'M', color: 'black'),
              ProductVariant(
                id: 'v2',
                size: 'L',
                color: 'black',
                available: false,
              ),
            ],
          ),
          servable: true,
          shoppable: true,
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      expect(find.text('M · black'), findsOneWidget);
      expect(find.text('L · black · Sold out'), findsOneWidget);
    });

    testWidgets('the delivery region comes from the server, never invented', (
      tester,
    ) async {
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
          deliveryCountries: const ['BD'],
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      expect(find.text('BD'), findsOneWidget);
      expect(
        find.text('Delivery region not listed by this store.'),
        findsNothing,
      );
    });

    testWidgets('an unlisted delivery region says so rather than guessing', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product()],
          detail: ProductDetail(product: _product(), servable: true),
        ),
      );
      await openFromFeed(tester);
      expect(
        find.text('Delivery region not listed by this store.'),
        findsOneWidget,
      );
    });
  });

  group('the screen itself', () {
    // The affiliate disclosure was moved off the product page and into the
    // published Privacy Policy on 2026-08-14 (founder call). Asserted as an
    // absence so the removal is deliberate and a re-add has to be deliberate
    // too, rather than the coverage just quietly disappearing.
    testWidgets('carries no per-product affiliate disclosure', (tester) async {
      await boot(tester, discover: _FakeDiscover(page1: [_product()]));
      await openFromFeed(tester);
      expect(
        find.text(
          'Wear The Mood may earn a commission from eligible purchases.',
        ),
        findsNothing,
      );
    });

    testWidgets('offers Save and Shop on a product that cannot be tried on', (
      tester,
    ) async {
      // §12's non-try-on pairing. The try-on-ready pairing is covered in the
      // shopping try-on suite.
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      expect(shopButton, findsOneWidget);
      expect(find.widgetWithText(GhostButton, 'Save'), findsOneWidget);
      // Never a second gradient CTA — one primary action per surface (§26.5).
      expect(find.byType(GradientCta), findsOneWidget);
    });

    testWidgets(
      'a product that is gone opens, explains, and cannot be shopped',
      (tester) async {
        // 404-ing would read as a broken link and strand the user (§11.3, §24).
        final repo = _FakeDiscover(
          page1: [_product()],
          detail: ProductDetail(
            product: _product(stock: StockStatus.outOfStock),
            servable: false,
            shoppable: false,
          ),
          similarItems: [_product(id: 'p9', title: 'Ivory column dress')],
        );
        await boot(tester, discover: repo);
        await openFromFeed(tester);

        expect(find.text('No longer available'), findsOneWidget);
        expect(tester.widget<GradientCta>(shopButton).onPressed, isNull);

        // And alternatives are offered rather than a dead end.
        await scrollDetails(tester);
        expect(find.text('SIMILAR PRODUCTS'), findsOneWidget);
      },
    );

    testWidgets('similar products are listed and open in place', (
      tester,
    ) async {
      final repo = _FakeDiscover(
        page1: [_product()],
        similarItems: [_product(id: 'p9', title: 'Ivory column dress')],
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);
      await scrollDetails(tester);

      expect(find.text('SIMILAR PRODUCTS'), findsOneWidget);
      expect(find.text('Ivory column dress'), findsOneWidget);
    });

    testWidgets('records the product as recently viewed', (tester) async {
      // Feeds the "keep a just-seen product out of the first positions" rule
      // and is a clearable user control (§33.3, §36).
      final store = _FakeStore();
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
        store: store,
      );
      await openFromFeed(tester);
      expect(store.viewed, ['p1']);
    });
  });

  group('the outbound click', () {
    testWidgets('opens only the URL the backend returned', (tester) async {
      final launcher = _FakeLauncher();
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickResult: _click,
      );
      await boot(tester, discover: repo, launcher: launcher);
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      // Exactly what the server said, and nothing the app assembled.
      expect(launcher.opened, [_click.url]);
      expect(repo.clickKeys, hasLength(1));
      expect(repo.clickKeys.single, isNotEmpty);
    });

    testWidgets('a retry reuses the same idempotency key', (tester) async {
      // A duplicate click inflates the click-through rate the funnel is judged
      // on, so the retry after a failure must be the SAME action (§9, §37.3).
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickError: const ApiException(
          code: ApiErrorCode.providerError,
          message: 'store down',
        ),
      );
      await boot(tester, discover: repo, launcher: _FakeLauncher());
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);
      expect(
        find.text("We couldn't open this store just now."),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(GhostButton, 'Try again'));
      await settle(tester);

      expect(repo.clickKeys, hasLength(2));
      expect(repo.clickKeys[0], repo.clickKeys[1]);
    });

    testWidgets('a product that is gone offers no retry', (tester) async {
      // Telling someone to try again when the product no longer exists is
      // advice that can never work (§24).
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickError: const ApiException(
          code: ApiErrorCode.notFound,
          message: 'gone',
        ),
      );
      await boot(tester, discover: repo, launcher: _FakeLauncher());
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      expect(find.text('No longer available'), findsWidgets);
      expect(find.widgetWithText(GhostButton, 'Try again'), findsNothing);
      // And the user is still on the product, not on an empty browser tab.
      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
    });

    testWidgets('a browser that refuses the URL is reported, not swallowed', (
      tester,
    ) async {
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickResult: _click,
      );
      await boot(
        tester,
        discover: repo,
        launcher: _FakeLauncher(succeeds: false),
      );
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      expect(
        find.text("We couldn't open this store just now."),
        findsOneWidget,
      );
      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
    });

    testWidgets('reports affiliate_click with the try-on state', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickResult: const AffiliateClick(
          clickId: 'c1',
          url: 'https://shop.example.test/p/1',
          merchant: MerchantSummary(id: 'm1', name: 'Studio Label'),
          tryOnCompleted: true,
        ),
      );
      await boot(
        tester,
        discover: repo,
        launcher: _FakeLauncher(),
        analytics: analytics,
      );
      await openFromFeed(tester);

      expect(analytics.events, contains(AnalyticsEvents.productOpen));

      await tester.tap(shopButton);
      await settle(tester);

      expect(analytics.events, contains(AnalyticsEvents.affiliateClick));
      final props = analytics.props[AnalyticsEvents.affiliateClick]!;
      expect(props[DiscoverAnalyticsProps.productId], 'p1');
      expect(props[DiscoverAnalyticsProps.merchantId], 'm1');
      expect(props[DiscoverAnalyticsProps.tryOnCompleted], true);
      // Nothing here may carry a destination or anything private (§22, §36).
      expect(props.values.join(), isNot(contains('http')));
    });

    testWidgets('a store that cannot be reached reports a typed failure', (
      tester,
    ) async {
      // Without this the §40 alert "redirect failures above 1% of click
      // attempts" has no numerator: a failed tap would be indistinguishable
      // from a tap that never happened.
      final analytics = _RecordingAnalytics();
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickError: const ApiException(
          code: ApiErrorCode.providerError,
          message: 'nope',
        ),
      );
      await boot(
        tester,
        discover: repo,
        launcher: _FakeLauncher(),
        analytics: analytics,
      );
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      expect(analytics.events, contains(AnalyticsEvents.affiliateClickFailed));
      // A failure must NOT also count as a click, or the failure rate it is
      // measured against can only ever fall.
      expect(analytics.events, isNot(contains(AnalyticsEvents.affiliateClick)));
      final props = analytics.props[AnalyticsEvents.affiliateClickFailed]!;
      expect(props[DiscoverAnalyticsProps.failureCode], 'unreachable');
      expect(props[DiscoverAnalyticsProps.productId], 'p1');
      expect(props.values.join(), isNot(contains('http')));
    });

    testWidgets('a browser that refuses the URL reports its own failure code', (
      tester,
    ) async {
      // Distinct from `unreachable`: the backend produced a valid destination
      // and already recorded the click. Merging the two would point an ops
      // alert at merchant configuration for what is a device problem.
      final analytics = _RecordingAnalytics();
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickResult: _click,
      );
      await boot(
        tester,
        discover: repo,
        launcher: _FakeLauncher(succeeds: false),
        analytics: analytics,
      );
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      final props = analytics.props[AnalyticsEvents.affiliateClickFailed]!;
      expect(props[DiscoverAnalyticsProps.failureCode], 'launch_failed');
      expect(analytics.events, isNot(contains(AnalyticsEvents.affiliateClick)));
    });

    testWidgets('a withdrawn product reports the unavailable failure code', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
        clickError: const ApiException(
          code: ApiErrorCode.notFound,
          message: 'gone',
        ),
      );
      await boot(
        tester,
        discover: repo,
        launcher: _FakeLauncher(),
        analytics: analytics,
      );
      await openFromFeed(tester);

      await tester.tap(shopButton);
      await settle(tester);

      expect(
        analytics.props[AnalyticsEvents
            .affiliateClickFailed]![DiscoverAnalyticsProps.failureCode],
        'unavailable',
      );
    });
  });

  group('saved synchronization', () {
    testWidgets('saving on Details flips the heart in the feed behind it', (
      tester,
    ) async {
      // Without the shared override layer the only fix would be reloading the
      // feed, which would throw away the scroll position (§11.3, §33.2).
      final repo = _FakeDiscover(
        page1: [_product()],
        detail: ProductDetail(
          product: _product(),
          servable: true,
          shoppable: true,
        ),
      );
      await boot(tester, discover: repo);
      await openFromFeed(tester);

      await tester.tap(find.widgetWithText(GhostButton, 'Save'));
      await settle(tester);
      expect(repo.savedCalls, ['p1']);

      await goBack(tester);

      final card = tester.widget<WtmProductCard>(
        find.byType(WtmProductCard).first,
      );
      expect(card.product.saved, isTrue);
    });
  });

  group('failure states', () {
    testWidgets('a failed refresh keeps the card the user tapped', (
      tester,
    ) async {
      // There IS something worth showing; replacing it with an error screen
      // would be a downgrade (§24).
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()], detailFails: true),
      );
      await openFromFeed(tester);

      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
      expect(find.text('Black silk dress'), findsWidgets);
      expect(find.byType(WtmErrorState), findsNothing);
    });

    testWidgets('a deep link to a product that will not load shows an error', (
      tester,
    ) async {
      // Nothing was handed in, so there is nothing to fall back to.
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()], detailFails: true),
        at: '${AppRoute.wtmProduct}?id=p1',
      );

      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.text("Couldn't load this product"), findsOneWidget);
    });

    testWidgets('a product link with no id lands on Discover, never blank', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
        at: AppRoute.wtmProduct,
      );
      expect(find.byType(WtmProductDetailsScreen), findsNothing);
      expect(find.text('Picked for You'), findsOneWidget);
    });
  });
}
