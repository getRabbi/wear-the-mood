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
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/data/repositories/news_repository.dart';
import 'package:app/data/repositories/offers_repository.dart';
import 'package:app/features/discover/application/product_feed.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_feed_modules.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_saved_screen.dart';
import 'package:app/ui/discover/wtm_shop_feed.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 3 UI: the product grid inside Discover, the save round trip, the
/// filter indicator, the three empty states, and pagination.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({
    List<Product>? page1,
    // Page 2 exists so the fake can express "there is more"; the pagination
    // trigger itself is scroll-driven and covered by the domain tests.
    this.page2 = const <Product>[],
    this.savedItems = const [],
    this.fails = false,
    this.regionEmpty = false,
  }) : page1 = page1 ?? const [];

  final List<Product> page1;
  final List<Product> page2;
  final List<SavedProduct> savedItems;
  final bool fails;
  final bool regionEmpty;

  final savedCalls = <String>[];
  final unsavedCalls = <String>[];
  final interactions = <String>[];
  String? lastQuery;
  int pageRequests = 0;

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
  }) async {
    pageRequests++;
    lastQuery = query;
    if (fails) throw Exception('catalog down');
    final page = cursor != null
        ? ProductPage(items: page2)
        : ProductPage(
            items: page1,
            nextCursor: page2.isEmpty ? null : 'cursor-2',
            regionEmpty: regionEmpty,
          );
    // The raw map only matters to the offline cache; these tests drive the UI,
    // so an empty envelope is honest rather than a hand-built duplicate.
    return ProductPageResult(page: page, raw: const {});
  }

  @override
  Future<List<SavedProduct>> saved() async => savedItems;

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
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// No disk in a widget test — the offline cache is covered by its own suite.
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
  MatchReason? reason,
  bool sponsored = false,
  String? category = 'dresses',
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: title,
  brand: 'Studio',
  category: category,
  price: Money(amountMinor: priceMinor, currency: 'BDT'),
  originalPrice: originalMinor == null
      ? null
      : Money(amountMinor: originalMinor, currency: 'BDT'),
  saved: saved,
  stockStatus: stock,
  matchReason: reason,
  sponsored: sponsored,
  trackingToken: 'p:$id',
);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  /// The save heart ON A PRODUCT CARD. Scoped, because the Discover header
  /// now carries a heart of its own for Saved.
  final heart = find.descendant(
    of: find.byType(WtmProductCard),
    matching: find.byWidgetPredicate(
      (w) => w is WtmIcon && w.glyph == WtmGlyph.heart,
    ),
  );

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required _FakeDiscover discover,
    bool shopping = true,
    List<WardrobeItem> closet = const [],
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
          (ref) => {FeatureFlags.discover, if (shopping) FeatureFlags.shopping},
        ),
        discoverRepositoryProvider.overrideWithValue(discover),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(closet),
        ),
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

  group('the shopping flag', () {
    testWidgets('OFF leaves the Stories rail up and the grid absent', (
      tester,
    ) async {
      // Two independent kill switches: shopping can go without Discover.
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product()]),
        shopping: false,
      );
      expect(find.byType(WtmShopFeed), findsNothing);
      expect(find.byType(WtmProductCard), findsNothing);
    });

    testWidgets('ON renders the Picked for You grid', (tester) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(id: 'p1'),
            _product(id: 'p2'),
          ],
        ),
      );
      expect(find.text('Picked for You'), findsOneWidget);
      expect(find.byType(WtmProductCard), findsNWidgets(2));
    });
  });

  group('the product card', () {
    testWidgets('shows brand, title, price and one match reason', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [_product(reason: MatchReason.closetMatch)],
        ),
      );
      expect(find.text('STUDIO'), findsOneWidget);
      expect(find.text('Black silk dress'), findsOneWidget);
      expect(find.text('Matches your closet'), findsOneWidget);
    });

    testWidgets(
      'an unknown match reason shows none rather than a placeholder',
      (tester) async {
        await boot(
          tester,
          discover: _FakeDiscover(
            page1: [_product(reason: MatchReason.unknown)],
          ),
        );
        expect(find.byType(WtmProductCard), findsOneWidget);
        expect(find.textContaining('unknown'), findsNothing);
      },
    );

    testWidgets('shows a real discount and never an invented one', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(id: 'p1', priceMinor: 350000, originalMinor: 500000),
            _product(id: 'p2', priceMinor: 350000),
          ],
        ),
      );
      expect(find.text('30% OFF'), findsOneWidget);
    });

    testWidgets('sold out wins over a discount — one badge only', (
      tester,
    ) async {
      // §26.11: no cramped badge stacking, and being unable to buy something
      // matters more than it being cheap.
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(
              priceMinor: 350000,
              originalMinor: 500000,
              stock: StockStatus.outOfStock,
            ),
          ],
        ),
      );
      expect(find.text('SOLD OUT'), findsOneWidget);
      expect(find.text('30% OFF'), findsNothing);
    });

    testWidgets('a sponsored product is labelled', (tester) async {
      // §39: never disguised as an organic personalized match.
      await boot(
        tester,
        discover: _FakeDiscover(page1: [_product(sponsored: true)]),
      );
      expect(find.text('Sponsored'), findsOneWidget);
    });

    testWidgets('opens Product Details and offers try-on', (tester) async {
      // Phase 4 built the details destination; Phase 5 built the try-on one.
      // The badge itself only renders for a product whose compatibility has
      // actually passed — covered in the shopping try-on suite.
      await boot(tester, discover: _FakeDiscover(page1: [_product()]));
      final card = tester.widget<WtmProductCard>(find.byType(WtmProductCard));
      expect(card.onTap, isNotNull);
      expect(card.onTryOn, isNotNull);
    });
  });

  group('saving', () {
    testWidgets('the heart persists and flips optimistically', (tester) async {
      final repo = _FakeDiscover(page1: [_product()]);
      await boot(tester, discover: repo);

      await tester.tap(heart);
      await settle(tester);

      expect(repo.savedCalls, ['p1']);
      // The behavioural signal rides along for ranking.
      expect(repo.interactions, contains('save:p1'));
    });

    testWidgets('unsaving an already-saved product calls unsave', (
      tester,
    ) async {
      final repo = _FakeDiscover(page1: [_product(saved: true)]);
      await boot(tester, discover: repo);

      await tester.tap(heart);
      await settle(tester);

      expect(repo.unsavedCalls, ['p1']);
    });
  });

  group('empty states are distinguishable', () {
    testWidgets('cold start invites rather than blanking', (tester) async {
      // §19.5: never a blank feed, and never a setup flow in the way.
      await boot(tester, discover: _FakeDiscover(page1: const []));
      expect(find.text('Start with a few picks'), findsOneWidget);
    });

    testWidgets('an unsupported region says so, not "remove a filter"', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(page1: const [], regionEmpty: true),
      );
      expect(find.text('Nothing shipping here yet'), findsOneWidget);
      expect(find.text('No products match'), findsNothing);
    });

    testWidgets('a catalog failure offers retry', (tester) async {
      await boot(tester, discover: _FakeDiscover(fails: true));
      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.text('Try again'), findsWidgets);
    });
  });

  group('feed rhythm on screen', () {
    testWidgets('a Complete Your Look module renders from the closet', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            for (var i = 0; i < 8; i++)
              _product(id: 'p$i', category: i.isEven ? 'shoes' : 'bags'),
          ],
        ),
        closet: const [
          WardrobeItem(id: 'w1', title: 'Black dress', category: 'dresses'),
        ],
      );

      expect(find.byType(WtmCompleteLookModule), findsOneWidget);
      expect(find.text('COMPLETE YOUR LOOK'), findsOneWidget);
      // ONE action on the module (§26.6).
      expect(find.text('See Matches'), findsOneWidget);
    });

    testWidgets('no closet means no module, never an empty one', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [for (var i = 0; i < 8; i++) _product(id: 'p$i')],
        ),
      );
      expect(find.byType(WtmCompleteLookModule), findsNothing);
    });
  });

  group('pagination', () {
    testWidgets('the next page appends and never reorders what is shown', (
      tester,
    ) async {
      // §33.2: an already rendered feed must not reshuffle under the user.
      final repo = _FakeDiscover(
        page1: [
          _product(id: 'p1'),
          _product(id: 'p2'),
        ],
        page2: [
          _product(id: 'p3'),
          _product(id: 'p4'),
        ],
      );
      final container = await boot(tester, discover: repo);
      expect(find.byType(WtmProductCard), findsNWidgets(2));

      await container.read(productFeedProvider.notifier).loadMore();
      await settle(tester);

      final state = container.read(productFeedProvider).asData!.value;
      expect(state.items.map((p) => p.id), ['p1', 'p2', 'p3', 'p4']);
    });

    testWidgets('a duplicate id from the server is dropped, not rendered', (
      tester,
    ) async {
      // The keyset cursor should make this impossible, but a duplicate KEY in
      // a list is a hard crash, so it is filtered rather than trusted.
      final repo = _FakeDiscover(
        page1: [
          _product(id: 'p1'),
          _product(id: 'p2'),
        ],
        page2: [
          _product(id: 'p2'),
          _product(id: 'p3'),
        ],
      );
      final container = await boot(tester, discover: repo);

      await container.read(productFeedProvider.notifier).loadMore();
      await settle(tester);

      final ids = container
          .read(productFeedProvider)
          .asData!
          .value
          .items
          .map((p) => p.id)
          .toList();
      expect(ids, ['p1', 'p2', 'p3']);
      expect(ids.toSet(), hasLength(ids.length));
    });

    testWidgets('an exhausted feed stops requesting pages', (tester) async {
      final repo = _FakeDiscover(page1: [_product()]);
      final container = await boot(tester, discover: repo);
      final before = repo.pageRequests;

      await container.read(productFeedProvider.notifier).loadMore();
      await container.read(productFeedProvider.notifier).loadMore();

      expect(repo.pageRequests, before);
    });
  });

  testWidgets('the filter indicator is compact, not a permanent chip row', (
    tester,
  ) async {
    // §11.2 / §26.1.
    await boot(tester, discover: _FakeDiscover(page1: [_product()]));
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Filters · 1'), findsNothing);
  });

  testWidgets('Saved opens and lists what was saved', (tester) async {
    final repo = _FakeDiscover(
      savedItems: [
        SavedProduct(
          product: _product(stock: StockStatus.outOfStock),
          savedAt: DateTime(2026, 8, 1),
          priceDropped: true,
        ),
      ],
    );
    await boot(tester, discover: repo, at: AppRoute.wtmSaved);

    expect(find.byType(WtmSavedScreen), findsOneWidget);
    // A sold-out saved product shows its state instead of vanishing (§11.3).
    expect(find.text('SOLD OUT'), findsOneWidget);
    expect(find.text('Price dropped since you saved it'), findsOneWidget);
  });
}
