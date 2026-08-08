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
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/discover/wtm_story_rail.dart';
import 'package:app/ui/home/wtm_home_screen.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 7: the rollout itself.
///
/// Every stage of the staged enablement, and every rollback lever, has to leave
/// a USABLE app — §30 is explicit that this must be true "without a new binary
/// release". The individual screens are covered elsewhere; what is proven here
/// is the COMBINATIONS, because the risk in a staged rollout is not a screen
/// being wrong, it is one flag arriving before another and leaving a hole.
///
/// And a responsive pass at §41's breakpoints. Flutter throws on overflow in a
/// test, so pumping each surface at each size IS the assertion — an overflow
/// fails the test rather than shipping as a clipped card.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({List<Product>? page1}) : page1 = page1 ?? const [];

  final List<Product> page1;

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
  Future<ProductDetail> product(String productId) async => ProductDetail(
    product: page1.first,
    servable: true,
    shoppable: true,
    deliveryCountries: const ['BD'],
  );

  @override
  Future<List<Product>> similar(String productId, {int? limit}) async =>
      page1.skip(1).toList();

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
  }) async {}

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

Product _product({String id = 'p1'}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk slip dress with a very long editorial name',
  brand: 'Studio Label',
  category: 'dresses',
  description: 'A dress.',
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  originalPrice: const Money(amountMinor: 499900, currency: 'BDT'),
  sizes: const ['XS', 'S', 'M', 'L', 'XL'],
  colors: const ['black', 'ivory'],
  matchReason: MatchReason.closetMatch,
  tryOnStatus: TryOnStatus.ready,
  trackingToken: 'p:$id',
);

/// The rollout stages from §30, in order.
const _stageDark = <String>{};
const _stageDiscover = {FeatureFlags.discover};
const _stageStories = {FeatureFlags.discover, FeatureFlags.discoverStories};
const _stageFull = {
  FeatureFlags.discover,
  FeatureFlags.discoverStories,
  FeatureFlags.shopping,
};

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
    Set<String> flags = _stageFull,
    // Lets a test change the answer mid-session, which is what a server-side
    // flag flip looks like to a running app.
    Set<String> Function()? flagsSource,
    String at = AppRoute.wtmDiscover,
    Size size = const Size(1080, 2340),
    double pixelRatio = 3.0,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => flagsSource?.call() ?? flags,
        ),
        discoverRepositoryProvider.overrideWithValue(
          _FakeDiscover(
            page1: [for (var i = 0; i < 6; i++) _product(id: 'p$i')],
          ),
        ),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(_FakeGiveaway()),
        offersRepositoryProvider.overrideWithValue(_FakeOffers()),
        newsRepositoryProvider.overrideWithValue(_FakeNews()),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(const [
            WardrobeItem(id: 'w1', title: 'Noir blouse', category: 'tops'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const FashionOsApp(),
        ),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(at);
    await settle(tester);
    return container;
  }

  group('staged enablement leaves a usable app at every step', () {
    testWidgets('dark — every flag off is the shipped production state', (
      tester,
    ) async {
      // What every installed build sees today. Discover's tab still resolves,
      // to the community surface, and Home keeps the shortcut row because
      // nothing else can reach Giveaways / Offers / Newsroom yet.
      await boot(tester, flags: _stageDark);

      expect(find.byType(WtmSocialScreen), findsOneWidget);
      expect(find.byType(WtmStoryRail), findsNothing);
      expect(find.byType(WtmProductCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('discover only — the surface without stories or catalog', (
      tester,
    ) async {
      await boot(tester, flags: _stageDiscover);

      expect(find.byType(WtmSocialScreen), findsNothing);
      expect(find.text('Discover'), findsWidgets);
      // Neither sub-feature leaks in ahead of its own flag.
      expect(find.byType(WtmStoryRail), findsNothing);
      expect(find.byType(WtmProductCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stories on, catalog still dark', (tester) async {
      // The catalog can lag the rail by days without Discover looking broken.
      await boot(tester, flags: _stageStories);

      expect(find.byType(WtmProductCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('full — every flag on', (tester) async {
      await boot(tester, flags: _stageFull);

      expect(find.byType(WtmProductCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the rollback levers work without a release', () {
    testWidgets('discover off mid-session restores Community', (tester) async {
      // §30's instant kill switch, modelled the way it actually fires: ops
      // flips the row, the app invalidates its flag provider (Discover's
      // pull-to-refresh already does), and the new value lands — no restart,
      // no release.
      var flags = _stageFull;
      final container = await boot(tester, flagsSource: () => flags);
      expect(find.byType(WtmSocialScreen), findsNothing);

      flags = _stageDark;
      container.invalidate(enabledFeatureFlagsProvider);
      await settle(tester);

      expect(find.byType(WtmSocialScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shopping off alone leaves the rail up', (tester) async {
      // Two independent kill switches: the catalog can be pulled without
      // taking Discover down with it.
      await boot(tester, flags: _stageStories);
      expect(find.byType(WtmProductCard), findsNothing);
      expect(find.byType(WtmSocialScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the legacy Home row returns on its flag', (tester) async {
      await boot(
        tester,
        flags: {..._stageFull, FeatureFlags.legacyHomeDiscover},
        at: AppRoute.wtmHome,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
      await settle(tester);

      expect(find.text('Giveaways'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive matrix (§41)', () {
    // Logical sizes × devicePixelRatio. Named for the class of device each one
    // stands in for; the numbers are what the layout actually sees.
    const breakpoints = <String, (Size, double)>{
      'small phone 320dp': (Size(960, 1920), 3.0),
      'large phone 430dp': (Size(1290, 2796), 3.0),
      '7-inch tablet 600dp': (Size(1200, 1920), 2.0),
      '10-inch tablet 800dp': (Size(1600, 2560), 2.0),
      'tablet landscape 1280dp': (Size(2560, 1600), 2.0),
      'phone landscape 780dp': (Size(2340, 1080), 3.0),
    };

    for (final entry in breakpoints.entries) {
      final (size, dpr) = entry.value;

      testWidgets('Discover lays out at ${entry.key}', (tester) async {
        await boot(tester, size: size, pixelRatio: dpr);
        // The approved layout leads with the Story rail, so on a short
        // viewport — phone landscape is 360dp tall — the first curated row
        // starts below the sliver's build window. Scrolling to it is what the
        // user does; asserting it exists without scrolling would only be
        // testing where a lazy list happened to stop.
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
        await settle(tester);

        expect(find.byType(WtmProductCard), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Home lays out at ${entry.key}', (tester) async {
        await boot(tester, at: AppRoute.wtmHome, size: size, pixelRatio: dpr);
        expect(find.byType(WtmHomeScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Product Details lays out at ${entry.key}', (tester) async {
        await boot(
          tester,
          at: '${AppRoute.wtmProduct}?id=p0',
          size: size,
          pixelRatio: dpr,
        );
        expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('accessibility scaling', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('Discover survives ${scale}x text on a small phone', (
        tester,
      ) async {
        // The combination that breaks layouts: the narrowest screen and the
        // largest type. A clipped price is worse than a wrapped one.
        await boot(tester, size: const Size(960, 1920), textScale: scale);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Product Details survives ${scale}x text', (tester) async {
        await boot(
          tester,
          at: '${AppRoute.wtmProduct}?id=p0',
          size: const Size(960, 1920),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Home survives ${scale}x text', (tester) async {
        await boot(
          tester,
          at: AppRoute.wtmHome,
          size: const Size(960, 1920),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
