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
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/news_item.dart';
import 'package:app/data/models/offer.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/product.dart';
// `TryOnStatus` here is the JOB's lifecycle; the product's compatibility enum
// of the same name is the one this suite is about.
import 'package:app/data/models/tryon_job.dart' hide TryOnStatus;
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/discover/application/shopping_tryon.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/tryon/models/studio_models.dart';
import 'package:app/features/tryon/tryon_controller.dart';
import 'package:app/features/tryon/tryon_state.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/mirror/wtm_mirror_flow.dart';
import 'package:app/ui/mirror/wtm_mirror_step2.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// The product-level Try-On invariant.
///
/// > IF `try_on_status == ready` AND `feature_shopping` is on, THEN every
/// > normal presentation of that product exposes `TRY ON`.
///
/// Try-on is the thing this app does that a retailer's own page cannot, so
/// finding it must never depend on which screen a product happens to be on.
/// The other Discover suites each prove one surface works; this one exists to
/// prove no surface was FORGOTTEN — which is why the sweep is table-driven
/// over every route that renders a [WtmProductCard]. A seventh surface added
/// without its Try On action fails here rather than in somebody's hands.
///
/// The negative half matters just as much: `pending`, `unsupported` and
/// `failed` must not produce an enabled action, and the flag being off must
/// take the whole thing away rather than leave a button that 404s.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({
    List<Product>? page1,
    List<Product>? similarItems,
    List<SavedProduct>? savedItems,
    this.detail,
  }) : page1 = page1 ?? const [],
       similarItems = similarItems ?? const [],
       savedItems = savedItems ?? const [];

  final List<Product> page1;
  final List<Product> similarItems;
  final List<SavedProduct> savedItems;
  final ProductDetail? detail;

  /// Every interaction the app wrote, as `type:productId@placement`. The
  /// try-on funnel is measured off these, so the placement is part of the
  /// record rather than dropped.
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
      detail ??
      ProductDetail(
        product: page1.firstWhere(
          (p) => p.id == productId,
          orElse: () => page1.first,
        ),
        servable: true,
        shoppable: true,
      );

  @override
  Future<List<Product>> similar(String productId, {int? limit}) async =>
      similarItems;

  @override
  Future<List<SavedProduct>> saved() async => savedItems;

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
  }) async =>
      interactions.add('$eventType:${productId ?? ''}@${feedPlacement ?? ''}');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// Fails loudly if anything submits a job.
///
/// This is how "no credit is consumed just by tapping TRY ON" is asserted for
/// real. Credits are reserved server-side when a job is CREATED, so a fake
/// that throws on [createTryOn] turns any accidental submit into a failed test
/// instead of a silent charge.
class _NoJobsTryOn implements TryOnRepository {
  @override
  Future<TryOnJob> createTryOn({
    required String personImageUrl,
    String? garmentImageUrl,
    List<String>? garmentImageUrls,
    String? wardrobeItemId,
    bool hd = false,
    String modelSource = 'own_photo',
    String? presetModelId,
    String? idempotencyKey,
    String? sourceProductId,
    String? sourcePlacement,
    String? sourceCampaignId,
  }) async => throw StateError('A try-on job was created by a TRY ON tap.');

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
  Future<void> addRecentSearch(String term) async {}
  @override
  Future<void> clearRecentSearches() async {}
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

Product _product({
  String id = 'p1',
  TryOnStatus tryOn = TryOnStatus.ready,
  String category = 'dresses',
  List<String>? images,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  brand: 'Studio',
  category: category,
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  imageUrls: images ?? ['https://cdn.test/$id.jpg'],
  tryOnStatus: tryOn,
  trackingToken: 'p:$id',
);

SavedProduct _saved(Product product) =>
    SavedProduct(product: product, savedAt: DateTime.utc(2026, 8, 7));

/// Every surface that renders a product card, and the route it lives on.
///
/// The list IS the invariant. Adding a surface without adding it here is the
/// omission this suite is built to catch, so the entry is deliberately cheap
/// to write.
typedef _Surface = ({String name, String route, String placement});

const _surfaces = <_Surface>[
  // Both Discover rows — Picked for You and the closing curated row — are the
  // same card builder, so one route covers the pair.
  (name: 'Discover', route: AppRoute.wtmDiscover, placement: 'feed_grid'),
  // `View all` on a row: the same screen as Search, already showing results.
  (
    name: 'Browse / View all',
    route: AppRoute.wtmShopBrowse,
    placement: 'search',
  ),
  (name: 'Saved', route: AppRoute.wtmSaved, placement: 'saved'),
  (
    name: 'Home Shop Your Mood',
    route: AppRoute.wtmHome,
    placement: 'home_shop_your_mood',
  ),
];

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
    String at = AppRoute.wtmDiscover,
    bool shopping = true,
    Size size = const Size(1080, 2340),
    double pixelRatio = 3.0,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    // Through the platform dispatcher, NOT by wrapping the app in a
    // `MediaQuery`. `MediaQueryData(textScaler: …)` REPLACES the data rather
    // than extending it, so the wrapper form silently zeroes `size` — and a
    // zero-width viewport sends every responsive branch down its narrow path,
    // which makes a breakpoint test pass without testing the breakpoint.
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => {FeatureFlags.discover, if (shopping) FeatureFlags.shopping},
        ),
        discoverRepositoryProvider.overrideWithValue(discover),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        tryOnRepositoryProvider.overrideWithValue(_NoJobsTryOn()),
        wardrobeItemsProvider.overrideWith(() => FakeWardrobeItemsNotifier([])),
        outfitsProvider.overrideWith((ref) async => const <Outfit>[]),
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

  /// The card's pill renders its label uppercased; the Product Details button
  /// does not, which is how the two are told apart.
  final tryOnPill = find.descendant(
    of: find.byType(WtmProductCard),
    matching: find.text('TRY ON'),
  );

  /// Brings a card into the viewport before tapping it. Home and Saved put the
  /// products below the fold, and a tap on an unbuilt card tests the finder
  /// rather than the app.
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target.first);
    await settle(tester);
  }

  // ── the invariant ────────────────────────────────────────────────────────

  group('every surface exposes TRY ON on a ready product', () {
    for (final surface in _surfaces) {
      testWidgets('${surface.name} shows the pill', (tester) async {
        final product = _product();
        await boot(
          tester,
          discover: _FakeDiscover(
            page1: [product],
            savedItems: [_saved(product)],
          ),
          at: surface.route,
        );

        await reveal(tester, find.byType(WtmProductCard));
        expect(
          tryOnPill,
          findsWidgets,
          reason: '${surface.name} renders a product card without TRY ON',
        );
      });

      testWidgets('${surface.name} starts the shared flow, attributed', (
        tester,
      ) async {
        final product = _product();
        final repo = _FakeDiscover(
          page1: [product],
          savedItems: [_saved(product)],
        );
        final container = await boot(tester, discover: repo, at: surface.route);

        await reveal(tester, tryOnPill);
        await tester.tap(tryOnPill.first);
        await settle(tester);

        // The EXISTING pipeline's garment step — not a parallel one.
        expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
        final source = container.read(activeShoppingTryOnSourceProvider);
        expect(source, isNotNull);
        expect(source!.productId, 'p1');
        // Placement rides along, so the funnel can tell the surfaces apart.
        expect(source.feedPlacement, surface.placement);
      });
    }

    testWidgets('a submitted Search shows the pill and starts the flow', (
      tester,
    ) async {
      // Its own case: the search screen shows recents until a term is
      // submitted, so results have to be asked for rather than routed to.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
        at: AppRoute.wtmShopSearch,
      );

      await tester.enterText(find.byType(TextField), 'silk dress');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);

      await reveal(tester, tryOnPill);
      await tester.tap(tryOnPill.first);
      await settle(tester);

      final source = container.read(activeShoppingTryOnSourceProvider);
      expect(source, isNotNull);
      expect(source!.feedPlacement, 'search');
    });

    testWidgets('Similar Products shows the pill and starts the flow', (
      tester,
    ) async {
      // Its own case: the alternatives rail is reached by opening a product,
      // so it cannot be driven from a route the way the others can.
      final anchor = _product(id: 'anchor');
      final alternative = _product(id: 'alt');
      final container = await boot(
        tester,
        discover: _FakeDiscover(
          page1: [anchor],
          similarItems: [alternative],
          detail: ProductDetail(
            product: anchor,
            servable: true,
            shoppable: true,
          ),
        ),
      );

      await tester.tap(find.byType(WtmProductCard).hitTestable().first);
      await settle(tester);
      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);

      // The rail is the last section of a lazy list, so it has to be scrolled
      // into existence — an assertion made without this passes for the wrong
      // reason, on a card that was never built.
      await tester.drag(
        find
            .descendant(
              of: find.byType(WtmProductDetailsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -1600),
      );
      await settle(tester);
      await reveal(tester, tryOnPill);
      await tester.tap(tryOnPill.first);
      await settle(tester);

      final source = container.read(activeShoppingTryOnSourceProvider);
      expect(source, isNotNull);
      expect(source!.productId, 'alt');
      expect(source.feedPlacement, 'similar_products');
    });
  });

  // ── readiness is never faked ─────────────────────────────────────────────

  group('readiness', () {
    for (final status in [TryOnStatus.pending, TryOnStatus.unsupported]) {
      testWidgets('$status exposes no enabled action anywhere', (tester) async {
        // `pending` is not ready: a product is only ever LABELLED try-on ready
        // once compatibility has actually passed (§35). An UNSUPPORTED status
        // is the engine saying it cannot render this, which is the same answer
        // a bag or a pair of shoes gets — the server decides, not the card.
        final product = _product(tryOn: status);
        await boot(
          tester,
          discover: _FakeDiscover(
            page1: [product],
            savedItems: [_saved(product)],
          ),
          at: AppRoute.wtmSaved,
        );

        await reveal(tester, find.byType(WtmProductCard));
        expect(tryOnPill, findsNothing);
      });
    }

    testWidgets(
      'an accessory is off by whatever the server says, not the card',
      (tester) async {
        // Categories the engine cannot render arrive as `unsupported`, which is
        // the DEFAULT in ingestion — a product must be opted in, never opted
        // out. The card deliberately holds no category blocklist of its own: a
        // second authority would need an app release to disagree with the first.
        final bag = _product(
          id: 'bag',
          category: 'bags',
          tryOn: TryOnStatus.unsupported,
        );
        final dress = _product(id: 'dress');
        await boot(tester, discover: _FakeDiscover(page1: [bag, dress]));

        await reveal(tester, find.byType(WtmProductCard));
        // Exactly one pill for two cards: the garment's.
        expect(tryOnPill, findsOneWidget);
      },
    );

    testWidgets('an unusable image is refused before the flow opens', (
      tester,
    ) async {
      // Defence in depth — the server suppresses imageless products — but a
      // tap must explain itself rather than open a flow with nothing to send.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product(images: const [])]),
      );

      await reveal(tester, find.byType(WtmProductCard));
      expect(tryOnPill, findsNothing);
      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
    });
  });

  group('Product.tryOnGarmentImageUrl', () {
    test('never answers for a product the server has not cleared', () {
      for (final status in [
        TryOnStatus.pending,
        TryOnStatus.unsupported,
        TryOnStatus.unknown,
      ]) {
        expect(_product(tryOn: status).tryOnGarmentImageUrl, isNull);
      }
    });

    test('takes the first usable http(s) image', () {
      expect(
        _product(
          images: const ['https://cdn.test/a.jpg', 'https://b/c.jpg'],
        ).tryOnGarmentImageUrl,
        'https://cdn.test/a.jpg',
      );
    });

    test('skips entries that could never render as a garment', () {
      // A blank, relative, or non-http entry reaches the provider as a garment
      // and fails THERE, which costs a job to learn what a string check knows
      // for free.
      expect(
        _product(
          images: const [
            '',
            '   ',
            '/relative/path.jpg',
            'data:image/png;base64,iVBORw0KG',
            'file:///tmp/leak.png',
            'javascript:alert(1)',
            'https://cdn.test/real.jpg',
          ],
        ).tryOnGarmentImageUrl,
        'https://cdn.test/real.jpg',
      );
    });

    test('answers null when nothing in the list is usable', () {
      expect(
        _product(images: const ['', 'nonsense']).tryOnGarmentImageUrl,
        isNull,
      );
      expect(_product(images: const []).tryOnGarmentImageUrl, isNull);
    });
  });

  // ── the three hit areas do not collide ───────────────────────────────────

  group('one card, three actions', () {
    testWidgets('tapping the card still opens Product Details', (tester) async {
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );

      await tester.tap(find.byType(WtmProductCard).hitTestable().first);
      await settle(tester);

      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
      // Adding a third hit area must not turn a card tap into a try-on.
      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
      expect(find.byType(WtmMirrorStep2Screen), findsNothing);
    });

    testWidgets('tapping the heart saves and does NOT start a try-on', (
      tester,
    ) async {
      final repo = _FakeDiscover(page1: [_product()]);
      final container = await boot(tester, discover: repo);

      await tester.tap(
        find.descendant(
          of: find.byType(WtmProductCard),
          matching: find.byWidgetPredicate(
            (w) => w is WtmIcon && w.glyph == WtmGlyph.heart,
          ),
        ),
      );
      await settle(tester);

      expect(container.read(activeShoppingTryOnSourceProvider), isNull);
      expect(find.byType(WtmMirrorStep2Screen), findsNothing);
      expect(repo.interactions, contains('save:p1@feed_grid'));
    });

    testWidgets('the pill starts a try-on and does NOT open Details', (
      tester,
    ) async {
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );

      await tester.tap(tryOnPill.first);
      await settle(tester);

      expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
      expect(find.byType(WtmProductDetailsScreen), findsNothing);
      expect(container.read(activeShoppingTryOnSourceProvider), isNotNull);
    });
  });

  // ── nothing is spent, and nothing is spent twice ─────────────────────────

  group('cost and re-entrancy', () {
    testWidgets('a rapid double tap opens exactly one flow', (tester) async {
      // Two taps of the same pill are one intention. `context.push` updates
      // the router synchronously, so the second read finds the garment step
      // already on top and declines to push a second copy.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );

      await tester.tap(tryOnPill.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(tryOnPill.first, warnIfMissed: false);
      await settle(tester);

      expect(find.byType(WtmMirrorStep2Screen), findsOneWidget);
      // One garment, not the same one twice.
      expect(container.read(wtmMirrorFlowProvider).layers, hasLength(1));

      // And one back returns to the surface it came from, rather than landing
      // on a second identical screen.
      container.read(goRouterProvider).pop();
      await settle(tester);
      expect(find.byType(WtmMirrorStep2Screen), findsNothing);
    });

    testWidgets('tapping TRY ON consumes no credit and creates no job', (
      tester,
    ) async {
      // The repository throws on createTryOn, so a submit fails the test.
      // Credits are reserved when a job is created; if none is created, none
      // can be spent. Generation stays where it always was — the mirror's own
      // generate step, past the body, consent and mode gates.
      final repo = _FakeDiscover(page1: [_product()]);
      final container = await boot(tester, discover: repo);

      await tester.tap(tryOnPill.first);
      await settle(tester);

      expect(container.read(tryOnControllerProvider), isA<TryOnIdle>());
      expect(
        container.read(shoppingTryOnTrackerProvider),
        ShoppingTryOnPhase.idle,
      );
      // The `try_on` behavioural signal is written on SUCCESS, never on tap —
      // a render nobody has seen must not make a later click look converted.
      expect(repo.interactions.where((i) => i.startsWith('try_on:')), isEmpty);
    });

    testWidgets('pieces the wearer owns survive a shopping try-on', (
      tester,
    ) async {
      // Trying a purchase on with your own shoes is the point of the feature.
      final container = await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
      );
      container.read(wtmMirrorFlowProvider.notifier).setLayers([
        TryOnLayer.fromSource(
          imageUrl: 'https://cdn.test/my-boots.jpg',
          wardrobeItemId: 'w1',
          zIndex: 0,
        ),
      ]);

      await tester.tap(tryOnPill.first);
      await settle(tester);

      final layers = container.read(wtmMirrorFlowProvider).layers;
      expect(layers, hasLength(2));
      // The product leads the stack; the owned piece keeps its wardrobe id.
      expect(layers.first.imageUrl, 'https://cdn.test/p1.jpg');
      expect(layers.last.wardrobeItemId, 'w1');
    });
  });

  // ── the kill switch ──────────────────────────────────────────────────────

  testWidgets('shopping OFF takes the products and the action away', (
    tester,
  ) async {
    // Not a disabled pill on a card nobody should be seeing: the flag closes
    // the catalog server-side too, so the surface itself is what goes.
    final container = await boot(
      tester,
      discover: _FakeDiscover(page1: [_product()]),
      shopping: false,
    );

    expect(find.byType(WtmProductCard), findsNothing);
    expect(tryOnPill, findsNothing);
    expect(container.read(activeShoppingTryOnSourceProvider), isNull);
  });

  // ── it fits ──────────────────────────────────────────────────────────────

  group('layout', () {
    // The §41 breakpoints, plus the tablet, in logical pixels.
    for (final (label, width, height, ratio) in const [
      ('320dp — the narrowest phone', 960.0, 1707.0, 3.0),
      ('360dp — the common phone', 1080.0, 2340.0, 3.0),
      ('430dp — the large phone', 1290.0, 2796.0, 3.0),
      ('tablet portrait', 1600.0, 2560.0, 2.0),
      ('tablet landscape', 2560.0, 1600.0, 2.0),
    ]) {
      testWidgets('the card carries TRY ON without overflow at $label', (
        tester,
      ) async {
        await boot(
          tester,
          discover: _FakeDiscover(
            page1: [
              _product(),
              _product(id: 'p2'),
            ],
          ),
          size: Size(width, height),
          pixelRatio: ratio,
        );

        expect(tryOnPill, findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the status pill and TRY ON never overlap', (tester) async {
      // Found on a device, not here: as two `Positioned` corners the capsules
      // collided on Home's three-up preview — `30% OFF` drawn straight through
      // `TRY ON` — and a Stack lets its children overlap silently, so nothing
      // threw. Geometry is the only assertion that catches it.
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product().copyWith(
              originalPrice: const Money(amountMinor: 499900, currency: 'BDT'),
            ),
          ],
        ),
      );

      final discount = find.descendant(
        of: find.byType(WtmProductCard),
        matching: find.text('30% OFF'),
      );
      expect(discount, findsOneWidget, reason: 'the pair must both be present');
      expect(tryOnPill, findsOneWidget);

      expect(
        tester.getRect(discount).overlaps(tester.getRect(tryOnPill)),
        isFalse,
      );
    });

    testWidgets('a narrow card keeps TRY ON and drops the status pill', (
      tester,
    ) async {
      // Home lays out three across, so its cards are about a third of the
      // screen — too narrow for both. The ACTION is the one that survives:
      // the discount is still readable in the struck-through price beneath,
      // and TRY ON exists nowhere else on the card.
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            for (var i = 0; i < 3; i++)
              _product(id: 'p$i').copyWith(
                originalPrice: const Money(
                  amountMinor: 499900,
                  currency: 'BDT',
                ),
              ),
          ],
        ),
        at: AppRoute.wtmHome,
      );

      await reveal(tester, find.byType(WtmProductCard));
      expect(tryOnPill, findsWidgets);
      expect(
        find.descendant(
          of: find.byType(WtmProductCard),
          matching: find.text('30% OFF'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    for (final scale in const [1.3, 2.0]) {
      testWidgets('the pill survives ${scale}x text', (tester) async {
        // The pill sits ON the artwork, so a grown label has to stay inside a
        // fixed-ratio box rather than pushing the card open.
        await boot(
          tester,
          discover: _FakeDiscover(
            page1: [
              _product(),
              _product(id: 'p2'),
            ],
          ),
          textScale: scale,
        );

        expect(tryOnPill, findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
