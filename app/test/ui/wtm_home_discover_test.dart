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
import 'package:app/data/models/money.dart';
import 'package:app/data/models/outfit.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/discover_repository.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/outfits/outfit_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/discover/wtm_story_rail.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// Phase 6: Home's `Shop Your Mood` preview, the retired shortcut row, and the
/// fallbacks that keep Home from ever showing an empty section.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({List<Product>? page1, this.regionEmpty = false})
    : page1 = page1 ?? const [];

  final List<Product> page1;
  final bool regionEmpty;
  final savedCalls = <String>[];

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
    page: ProductPage(items: page1, regionEmpty: regionEmpty),
    raw: const {},
  );

  @override
  Future<ProductDetail> product(String productId) async =>
      ProductDetail(product: page1.first, servable: true);

  @override
  Future<List<Product>> similar(String productId, {int? limit}) async =>
      const [];

  @override
  Future<List<SavedProduct>> saved() async => const [];

  @override
  Future<void> save(
    String productId, {
    bool priceAlert = true,
    bool availabilityAlert = false,
  }) async => savedCalls.add(productId);

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

class _NoCache implements DiscoverFeedCache {
  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key) async => null;
  @override
  Future<void> write(DiscoverFeedCacheKey key, Map<String, dynamic> r) async {}
  @override
  Future<void> clear() async {}
}

Product _product({String id = 'p1', String title = 'Black silk dress'}) =>
    Product(
      id: id,
      merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
      title: title,
      brand: 'Studio',
      category: 'dresses',
      price: const Money(amountMinor: 349900, currency: 'BDT'),
      trackingToken: 'p:$id',
    );

const _closet = [
  WardrobeItem(id: 'w1', title: 'Silk shirt', cutoutUrl: 'https://x/1.png'),
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
    _FakeDiscover? discover,
    bool shopping = true,
    bool discoverTab = true,
    bool legacyHome = false,
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
          (ref) => {
            if (discoverTab) FeatureFlags.discover,
            if (shopping) FeatureFlags.shopping,
            if (legacyHome) FeatureFlags.legacyHomeDiscover,
          },
        ),
        discoverRepositoryProvider.overrideWithValue(
          discover ?? _FakeDiscover(page1: [_product()]),
        ),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(_closet),
        ),
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
    container.read(goRouterProvider).go(AppRoute.wtmHome);
    await settle(tester);
    return container;
  }

  final giveawaysTile = find.text('Giveaways');

  /// Home is a lazy list and the shortcut row sits below the fold, so an
  /// assertion made without scrolling passes for the wrong reason — the row was
  /// never built rather than never rendered.
  Future<void> scrollToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1400));
    await settle(tester);
  }

  group('Shop Your Mood', () {
    testWidgets('previews three products with a way into Discover', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            _product(id: 'p1'),
            _product(id: 'p2'),
            _product(id: 'p3'),
            _product(id: 'p4'),
          ],
        ),
      );

      expect(find.text('SHOP YOUR MOOD'), findsOneWidget);
      // Three, not the whole feed: this is a window onto Discover, not a
      // second copy of it (§10, §26.9).
      expect(find.byType(WtmProductCard), findsNWidgets(3));
      expect(find.text('View all'), findsOneWidget);
      // And the old random row is gone when there is a catalog to show.
      expect(find.text('INSPIRATION FOR YOU'), findsNothing);
    });

    testWidgets('never duplicates the Discover Stories rail', (tester) async {
      // §10 and anti-clutter rule 9 both forbid it by name.
      await boot(tester);
      expect(find.byType(WtmStoryRail), findsNothing);
    });

    testWidgets('a preview product opens Product Details', (tester) async {
      await boot(tester);
      // The preview sits low on Home; scroll it into the viewport so the tap
      // lands on the card rather than on nothing.
      await tester.ensureVisible(find.byType(WtmProductCard).first);
      await settle(tester);
      await tester.tap(find.byType(WtmProductCard).first);
      await settle(tester);

      final screen = tester.widget<WtmProductDetailsScreen>(
        find.byType(WtmProductDetailsScreen),
      );
      expect(screen.productId, 'p1');
      // Attributed to Home, so the funnel can tell it from a Discover tap.
      expect(screen.placement, 'home');
    });

    testWidgets('saving from Home goes through the shared save state', (
      tester,
    ) async {
      final repo = _FakeDiscover(page1: [_product()]);
      await boot(tester, discover: repo);

      await tester.tap(
        find.descendant(
          of: find.byType(WtmProductCard),
          matching: find.byWidgetPredicate(
            (w) => w is WtmIcon && w.glyph == WtmGlyph.heart,
          ),
        ),
      );
      await settle(tester);

      expect(repo.savedCalls, ['p1']);
      final card = tester.widget<WtmProductCard>(find.byType(WtmProductCard));
      expect(card.product.saved, isTrue);
    });

    testWidgets('Home keeps everything §10 says to keep', (tester) async {
      await boot(tester);

      expect(find.byType(WtmSlider), findsOneWidget); // mood slider
      expect(find.text('Try-On\nStudio'), findsOneWidget);
      expect(find.text('Smart\nCloset'), findsOneWidget);
      expect(find.text('AI\nStylist'), findsOneWidget);
      expect(find.text('Outfit\nMaker'), findsOneWidget);
      expect(find.text("TODAY'S LOOK"), findsOneWidget);
    });
  });

  group('fallbacks — Home never shows an empty section', () {
    testWidgets('shopping off keeps the old inspiration row', (tester) async {
      // The fallback §10 asks to keep until Discover is proven.
      await boot(tester, shopping: false);

      expect(find.text('SHOP YOUR MOOD'), findsNothing);
      expect(find.text('INSPIRATION FOR YOU'), findsOneWidget);
    });

    testWidgets('an empty catalog keeps the old inspiration row', (
      tester,
    ) async {
      await boot(tester, discover: _FakeDiscover(page1: const []));

      expect(find.text('SHOP YOUR MOOD'), findsNothing);
      expect(find.text('INSPIRATION FOR YOU'), findsOneWidget);
    });

    testWidgets('a region with no catalog says so instead of faking one', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(page1: const [], regionEmpty: true),
      );

      expect(
        find.textContaining('Nothing shipping to you yet'),
        findsOneWidget,
      );
      expect(find.byType(WtmProductCard), findsNothing);
    });
  });

  group('the legacy shortcut row', () {
    testWidgets('is gone once Discover owns those destinations', (
      tester,
    ) async {
      await boot(tester);
      await scrollToBottom(tester);
      expect(giveawaysTile, findsNothing);
    });

    testWidgets('comes back when ops flips the fallback flag', (tester) async {
      // The lever that restores it without a binary release (§30).
      await boot(tester, legacyHome: true);
      await scrollToBottom(tester);
      expect(giveawaysTile, findsOneWidget);
    });

    testWidgets('stays while Discover is off, or nothing can reach them', (
      tester,
    ) async {
      // Giveaways, Offers and Newsroom live in the Discover branch now.
      // Removing the row before Discover is on would strand all three.
      await boot(tester, discoverTab: false, shopping: false);
      await scrollToBottom(tester);
      expect(giveawaysTile, findsOneWidget);
    });
  });
}
