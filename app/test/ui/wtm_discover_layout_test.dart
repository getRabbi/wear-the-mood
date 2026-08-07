import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
import 'package:app/features/discover/application/shopping_tryon.dart';
import 'package:app/features/discover/data/discover_feed_cache.dart';
import 'package:app/features/discover/data/discover_local_store.dart';
import 'package:app/features/discover/domain/discover_feed.dart';
import 'package:app/features/discover/domain/discover_page.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/theme/wtm_discover_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:app/ui/discover/wtm_daily_pulse.dart';
import 'package:app/ui/discover/wtm_discover_artwork.dart';
import 'package:app/ui/discover/wtm_discover_sections.dart';
import 'package:app/ui/discover/wtm_feed_modules.dart';
import 'package:app/ui/discover/wtm_product_card.dart';
import 'package:app/ui/discover/wtm_product_details_screen.dart';
import 'package:app/ui/discover/wtm_shop_feed.dart';
import 'package:app/ui/discover/wtm_story_rail.dart';
import 'package:app/ui/home/wtm_mood.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// The redesigned Discover composition (prototype `wearthemood_discover_prototype_v1`).
///
/// What this suite is actually protecting: the ORDER of the surface, the cap
/// on how many products can sit in one band, and the fact that the three
/// working actions — open, save, try on — survived the re-layout. Plus the
/// sizes it has to hold up at, from a 320dp phone to a landscape tablet at 2x
/// text.

class _FakeDiscover implements DiscoverRepository {
  _FakeDiscover({List<Product>? page1, this.fails = false})
    : page1 = page1 ?? const [];

  final List<Product> page1;
  final bool fails;

  final savedCalls = <String>[];
  final unsavedCalls = <String>[];

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
    if (fails) throw Exception('catalog down');
    // One page only: the feed has to be finite for the bottom-inset check to
    // have a real end to scroll to.
    return ProductPageResult(
      page: ProductPage(items: page1),
      raw: const {},
    );
  }

  @override
  Future<ProductDetail> product(String productId) async => ProductDetail(
    product: page1.firstWhere((p) => p.id == productId),
    servable: true,
    shoppable: true,
  );

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
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway(this.items);
  final List<Giveaway> items;

  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async =>
      items;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOffers implements OffersRepository {
  _FakeOffers(this.items);
  final List<Offer> items;

  @override
  Future<List<Offer>> getToday() async => items;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeNews implements NewsRepository {
  _FakeNews(this.items);
  final List<NewsItem> items;

  @override
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async =>
      items;
  @override
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeStore implements DiscoverLocalStore {
  @override
  Future<Map<String, int>> seenStoryVersions() async => const {};
  @override
  Future<void> markStorySeen(String id, int version) async {}
  @override
  Future<List<String>> recentSearches() async => const [];
  @override
  Future<(String?, String?, int)> shoppingScope() async => (null, null, 0);
  @override
  Future<void> setShoppingScope(String? c, String? cur, int v) async {}
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

/// In-memory mood storage. The real one is secure storage, which has no
/// platform channel in a widget test — so without this the write the module
/// makes could never be read back and the header could never agree with it.
class _FakeMoodStore extends WtmMoodRepository {
  _FakeMoodStore() : super(const FlutterSecureStorage());

  double? value;

  @override
  Future<double?> read() async => value;

  @override
  Future<void> write(double v) async => value = v;
}

class _NoCache implements DiscoverFeedCache {
  @override
  Future<DiscoverFeedCacheEntry?> read(DiscoverFeedCacheKey key) async => null;
  @override
  Future<void> write(DiscoverFeedCacheKey key, Map<String, dynamic> r) async {}
  @override
  Future<void> clear() async {}
}

final _giveaway = Giveaway(
  id: 'g1',
  ownerId: 'u2',
  title: 'Vintage shoulder bag',
  status: 'available',
  createdAt: DateTime(2026, 8, 1),
);

const _offer = Offer(
  id: 'o1',
  title: 'Across the new collection',
  brand: 'ZARA',
  discountLabel: '15% Off',
  affiliateUrl: 'https://zara.test',
);

final _news = NewsItem(
  id: 'a1',
  title: 'One black dress, three evening moods',
  source: 'Atelier Desk',
  createdAt: DateTime(2026, 8, 1),
);

/// Rotating categories, so Complete Your Look has different things to pair.
const _categories = ['shoes', 'bags', 'jewellery', 'outerwear', 'knitwear'];

Product _product(int i, {bool tryOn = false}) => Product(
  id: 'p$i',
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Piece number $i',
  brand: 'Studio',
  category: _categories[i % _categories.length],
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  imageUrls: const ['https://cdn.test/p.jpg'],
  tryOnStatus: tryOn ? TryOnStatus.ready : TryOnStatus.unsupported,
  trackingToken: 'p:p$i',
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

  /// Boots Discover at [size] logical pixels.
  Future<ProviderContainer> boot(
    WidgetTester tester, {
    Size size = const Size(430, 932),
    double textScale = 1.0,
    int productCount = 12,
    bool tryOnReady = false,
    bool shopping = true,
    bool giveaways = true,
    bool offers = true,
    bool news = true,
    bool catalogFails = false,
    List<WardrobeItem> closet = const [],
    _FakeDiscover? discover,
    WtmMoodRepository? mood,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repo =
        discover ??
        _FakeDiscover(
          page1: [
            for (var i = 0; i < productCount; i++)
              _product(i, tryOn: tryOnReady),
          ],
          fails: catalogFails,
        );

    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => {
            FeatureFlags.discover,
            FeatureFlags.discoverStories,
            if (shopping) FeatureFlags.shopping,
          },
        ),
        discoverRepositoryProvider.overrideWithValue(repo),
        discoverLocalStoreProvider.overrideWithValue(_FakeStore()),
        discoverFeedCacheProvider.overrideWithValue(_NoCache()),
        giveawayRepositoryProvider.overrideWithValue(
          _FakeGiveaway(giveaways ? [_giveaway] : const []),
        ),
        offersRepositoryProvider.overrideWithValue(
          _FakeOffers(offers ? const [_offer] : const []),
        ),
        newsRepositoryProvider.overrideWithValue(
          _FakeNews(news ? [_news] : const []),
        ),
        wardrobeItemsProvider.overrideWith(
          () => FakeWardrobeItemsNotifier(closet),
        ),
        if (mood != null) wtmMoodRepositoryProvider.overrideWithValue(mood),
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
    container.read(goRouterProvider).go(AppRoute.wtmDiscover);
    await settle(tester);
    return container;
  }

  /// The Discover page's own vertical scrollable — not the rail's, and not a
  /// strip's.
  Finder pageScrollable() => find
      .ancestor(
        of: find.byType(WtmDailyPulse),
        matching: find.byType(Scrollable),
      )
      .last;

  /// Every band currently laid out, top to bottom.
  ///
  /// Reading positions rather than the element tree, because a sliver builds
  /// its children in whatever order it likes; what the user sees is geometry.
  List<String> bands(WidgetTester tester) {
    final found = <(double, String)>[];
    void collect(Finder finder, String name) {
      for (final element in finder.evaluate()) {
        final box = element.renderObject;
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        found.add((box.localToGlobal(Offset.zero).dy, name));
      }
    }

    collect(find.byType(WtmStoryRail), 'rail');
    collect(find.byType(WtmStoryFallbackCard), 'rail');
    collect(find.byType(WtmDailyPulse), 'pulse');
    collect(find.byType(WtmProductStrip), 'products');
    collect(find.byType(WtmCompleteLookModule), 'complete-look');
    collect(find.byType(WtmFeatureCard), 'campaign');
    collect(find.byType(WtmEditorialCard), 'newsroom');
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final entry in found) entry.$2];
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    // A sliver only builds what is near the viewport, so each jump can reveal
    // more content and push the end further away. One jump used to be enough
    // when the page was three bands; the approved composition is longer, so
    // this jumps until the extent actually stops moving.
    // Resolved once: the pulse it is found through scrolls out of the built
    // range on the first jump, and the scrollable itself never goes away.
    final scrollable = tester.state<ScrollableState>(pageScrollable());
    var previous = -1.0;
    for (var i = 0; i < 12; i++) {
      final target = scrollable.position.maxScrollExtent;
      if (target == previous) break;
      previous = target;
      scrollable.position.jumpTo(target);
      await settle(tester);
    }
  }

  group('the approved composition', () {
    testWidgets('renders in the order the prototype fixes', (tester) async {
      // Tall viewport so the whole feed is laid out at once and the order can
      // be read without pagination interfering.
      await boot(
        tester,
        size: const Size(430, 4200),
        closet: const [
          WardrobeItem(id: 'w1', title: 'Black dress', category: 'dresses'),
        ],
      );

      expect(bands(tester).take(7), [
        'rail',
        'pulse',
        'products',
        'complete-look',
        'campaign',
        'newsroom',
        'products',
      ]);
    });

    testWidgets('the Story rail is up and is not repeated below', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200));
      expect(find.byType(WtmStoryRail), findsOneWidget);
      expect(bands(tester).where((b) => b == 'rail'), hasLength(1));
    });

    testWidgets('never more than four product cards in one band', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200), productCount: 16);

      final strips = find.byType(WtmProductStrip);
      expect(strips, findsWidgets);
      for (var i = 0; i < strips.evaluate().length; i++) {
        final cards = find
            .descendant(of: strips.at(i), matching: find.byType(WtmProductCard))
            .evaluate()
            .length;
        expect(
          cards,
          lessThanOrEqualTo(DiscoverFeedComposer.productsPerStrip),
          reason: 'band $i holds more than one screenful of products',
        );
      }
    });

    testWidgets('each product band after the lead carries its own heading', (
      tester,
    ) async {
      // A heading is what makes a band a band; without one the tail would read
      // as the wall of products this redesign replaced. And every heading is
      // DIFFERENT: "Keep exploring" introducing four rows down one scroll is
      // the exact defect this composition removes.
      await boot(tester, size: const Size(430, 4200), productCount: 12);

      final headings = [
        for (final slot in DiscoverRowSlot.values)
          wtmDiscoverRowCopy(
            AppLocalizations.of(tester.element(find.byType(WtmDailyPulse))),
            slot,
          ).title,
      ];
      expect(headings.toSet(), hasLength(headings.length));

      // 12 products at four per row is three rows, each under its own heading.
      expect(find.text(headings[0]), findsOneWidget); // Picked for You
      expect(find.text(headings[1]), findsOneWidget); // New for your mood
      expect(find.text(headings[2]), findsOneWidget); // More to explore
      expect(find.byType(WtmProductStrip), findsNWidgets(3));
    });

    testWidgets('the Complete Your Look module leads the mixed block', (
      tester,
    ) async {
      await boot(
        tester,
        size: const Size(430, 4200),
        closet: const [
          WardrobeItem(id: 'w1', title: 'Black dress', category: 'dresses'),
        ],
      );

      expect(find.byType(WtmCompleteLookModule), findsWidgets);
      expect(find.text('COMPLETE YOUR LOOK'), findsWidgets);
      // ONE action on the module (§26.6).
      expect(find.text('See Matches'), findsWidgets);
    });

    testWidgets('no closet means no module, never an empty one', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200));
      expect(find.byType(WtmCompleteLookModule), findsNothing);
      expect(bands(tester), isNot(contains('complete-look')));
    });

    testWidgets('the Giveaway card is editorial and has one action', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200));

      expect(find.byType(WtmFeatureCard), findsOneWidget);
      expect(find.text('Something to win'), findsOneWidget);
      final card = tester.widget<WtmFeatureCard>(find.byType(WtmFeatureCard));
      expect(card.actionLabel, 'View Giveaway');
      // §9.2: no second CTA competing with the giveaway itself.
      expect(
        find.descendant(
          of: find.byType(WtmFeatureCard),
          matching: find.byType(GradientCta),
        ),
        findsNothing,
      );
    });

    testWidgets('an Offer stands in when no giveaway is live', (tester) async {
      await boot(tester, size: const Size(430, 4200), giveaways: false);

      expect(find.text('A better price'), findsOneWidget);
      final card = tester.widget<WtmFeatureCard>(find.byType(WtmFeatureCard));
      expect(card.actionLabel, 'View Offer');
    });

    testWidgets('the Newsroom card is the split editorial card', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200));

      expect(find.byType(WtmEditorialCard), findsOneWidget);
      expect(find.text('A quick read'), findsOneWidget);
      expect(find.text('One black dress, three evening moods'), findsWidgets);
    });

    testWidgets('one eligible story is not shown twice in one viewport', (
      tester,
    ) async {
      // Caught on device: with only a Newsroom item live, the rail collapsed
      // to its compact fallback card AND the same Style Note rendered again as
      // the feed's editorial card. The fallback card already IS the whole
      // story, so the feed module stands down.
      // Shopping off as well, so the three personalized cards have no catalog
      // behind them either and the Newsroom item really is the only story.
      await boot(
        tester,
        size: const Size(430, 4200),
        shopping: false,
        giveaways: false,
        offers: false,
      );

      expect(find.byType(WtmStoryFallbackCard), findsOneWidget);
      expect(find.byType(WtmEditorialCard), findsNothing);
      expect(find.byType(WtmFeatureCard), findsNothing);
    });

    testWidgets('a full rail still earns its editorial cards beside it', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 4200));
      expect(find.byType(WtmStoryRail), findsOneWidget);
      expect(find.byType(WtmFeatureCard), findsOneWidget);
      expect(find.byType(WtmEditorialCard), findsOneWidget);
    });

    testWidgets('a nameless closet item never heads a "Your " module', (
      tester,
    ) async {
      await boot(
        tester,
        size: const Size(430, 4200),
        closet: const [WardrobeItem(id: 'w0')],
      );
      expect(find.byType(WtmCompleteLookModule), findsNothing);
      expect(find.textContaining('Your '), findsNothing);
    });

    testWidgets('both editorial cards hold their slot with nothing live', (
      tester,
    ) async {
      // The two editorial slots are fixed furniture — they stay put so the page
      // keeps its rhythm and Giveaways and the Newsroom keep an entry point
      // here. Empty means an honest invitation with a real destination, never
      // a placeholder dressed up as a campaign.
      await boot(
        tester,
        size: const Size(430, 4200),
        giveaways: false,
        offers: false,
        news: false,
      );

      expect(find.byType(WtmFeatureCard), findsOneWidget);
      expect(find.byType(WtmEditorialCard), findsOneWidget);
      expect(find.text('Nothing live right now'), findsOneWidget);
      expect(find.text('Browse giveaways'), findsOneWidget);
      expect(find.text('No new style notes'), findsOneWidget);
      // The editorial card's action is spoken rather than drawn — the same as
      // when it carries a real article — so this is where it has to be checked.
      expect(find.bySemanticsLabel(RegExp('Open Newsroom')), findsOneWidget);
      expect(find.byType(WtmProductStrip), findsWidgets);
    });
  });

  group('the Story rail is a rail', () {
    testWidgets('at least two portrait cards are in view at once', (
      tester,
    ) async {
      // The prototype shows roughly 2.5 cards. Fewer than two visible is a
      // banner, not a rail, and a banner is what the rejected build had.
      await boot(tester);

      final viewport =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      var inView = 0;
      for (final element in find.byType(WtmStoryCard).evaluate()) {
        final box = element.renderObject! as RenderBox;
        final left = box.localToGlobal(Offset.zero).dx;
        if (left < viewport && left + box.size.width > 0) inView++;
        // Portrait: the prototype's card is 132×194.
        expect(box.size.height, greaterThan(box.size.width));
      }
      expect(inView, greaterThanOrEqualTo(2));
    });

    testWidgets('a third card is at least partially visible', (tester) async {
      await boot(tester);
      final viewport =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final lefts = [
        for (final element in find.byType(WtmStoryCard).evaluate())
          (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
      ]..sort();
      expect(lefts.length, greaterThanOrEqualTo(3));
      // The third card starts before the right edge — that is the "2.5 cards"
      // cue that tells the user the rail scrolls.
      expect(lefts[2], lessThan(viewport));
    });
  });

  group('product artwork', () {
    testWidgets('draws the real image widget when the product has a URL', (
      tester,
    ) async {
      await boot(tester);

      final artwork = tester.widget<WtmDiscoverArtwork>(
        find
            .descendant(
              of: find.byType(WtmProductCard).first,
              matching: find.byType(WtmDiscoverArtwork),
            )
            .first,
      );
      expect(artwork.url, 'https://cdn.test/p.jpg');
      // Seeded per product, so a fallback is never the same drawing twice in
      // one row.
      expect(artwork.seed, isNotEmpty);
      expect(
        find.descendant(
          of: find.byType(WtmProductCard).first,
          matching: find.byType(CachedNetworkImage),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a product with no image gets the drawn fallback, not a hole', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            Product(
              id: 'noimg',
              merchant: const MerchantSummary(id: 'm1', name: 'Studio'),
              title: 'No picture',
              category: 'tops',
              price: const Money(amountMinor: 1000, currency: 'BDT'),
            ),
          ],
        ),
      );

      expect(
        find.descendant(
          of: find.byType(WtmProductCard),
          matching: find.byKey(wtmArtworkFallbackKey),
        ),
        findsOneWidget,
      );
      // Never the network widget for a product that has no URL to fetch.
      expect(
        find.descendant(
          of: find.byType(WtmProductCard),
          matching: find.byType(CachedNetworkImage),
        ),
        findsNothing,
      );
    });

    testWidgets('two products in a row do not draw the same fallback', (
      tester,
    ) async {
      await boot(
        tester,
        discover: _FakeDiscover(
          page1: [
            for (var i = 0; i < 4; i++)
              Product(
                id: 'blank$i',
                merchant: const MerchantSummary(id: 'm1', name: 'Studio'),
                title: 'Piece $i',
                category: 'tops',
                price: const Money(amountMinor: 1000, currency: 'BDT'),
              ),
          ],
        ),
      );

      final seeds = [
        for (final element
            in find
                .descendant(
                  of: find.byType(WtmProductCard),
                  matching: find.byType(WtmDiscoverArtwork),
                )
                .evaluate())
          (element.widget as WtmDiscoverArtwork).seed,
      ];
      expect(seeds, hasLength(4));
      expect(seeds.toSet(), hasLength(4));
    });
  });

  group('the working actions survived the re-layout', () {
    testWidgets('a product card opens Product Details', (tester) async {
      await boot(tester, productCount: 4);

      await tester.tap(find.byType(WtmProductCard).first);
      await settle(tester);

      expect(find.byType(WtmProductDetailsScreen), findsOneWidget);
    });

    testWidgets('the heart saves', (tester) async {
      final repo = _FakeDiscover(page1: [_product(0), _product(1)]);
      await boot(tester, discover: repo);

      await tester.tap(
        find
            .descendant(
              of: find.byType(WtmProductCard).first,
              matching: find.byWidgetPredicate(
                (w) => w is WtmIcon && w.glyph == WtmGlyph.heart,
              ),
            )
            .first,
      );
      await settle(tester);

      expect(repo.savedCalls, ['p0']);
    });

    testWidgets('the Try On badge starts a shopping try-on', (tester) async {
      final container = await boot(tester, productCount: 4, tryOnReady: true);

      final badge = find.descendant(
        of: find.byType(WtmProductCard),
        matching: find.text('TRY ON'),
      );
      expect(badge, findsWidgets);

      await tester.tap(badge.first);
      await settle(tester);

      // The existing pipeline was handed the product, with its placement
      // carried through for the try-on-to-shop funnel (§13).
      final source = container.read(shoppingTryOnSourceProvider);
      expect(source?.productId, 'p0');
      expect(source?.feedPlacement, 'feed_grid');
    });

    testWidgets('the mood module writes the mood the header names', (
      tester,
    ) async {
      // The one interactive module has to do something real: it writes through
      // the app's existing mood store, and the personalization line directly
      // above it says so on the next frame.
      final mood = _FakeMoodStore();
      await boot(tester, productCount: 4, mood: mood);

      expect(find.byType(WtmDailyPulse), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(WtmDailyPulse),
          matching: find.text('Rebel'),
        ),
      );
      await settle(tester);

      expect(mood.value, greaterThan(0.75));
      // The line is a rich span so the mood word can be gold, which is why
      // this reads through `findRichText` rather than matching a flat string.
      expect(
        find.textContaining('Fresh picks for your', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Rebel', findRichText: true), findsWidgets);
    });

    testWidgets('the mood word in the header is gold, the rest is not', (
      tester,
    ) async {
      // `.subtitle strong` — the one word that is personalized is the one word
      // that is emphasized.
      final mood = _FakeMoodStore()..value = 0.62;
      await boot(tester, productCount: 4, mood: mood);

      final rich = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.textSpan != null &&
              w.textSpan!.toPlainText().contains('Fresh picks for your'),
        ),
      );
      final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
      final gold = spans.firstWhere((s) => s.text == 'Bold');
      expect(gold.style?.color, DiscoverTokens.gold);
      expect(gold.style?.fontWeight, FontWeight.w600);
    });
  });

  group('sizes it has to hold up at', () {
    for (final (name, size) in const [
      ('a 320dp phone', Size(320, 640)),
      ('a 430dp phone', Size(430, 932)),
      ('a tablet in portrait', Size(834, 1194)),
      ('a tablet in landscape', Size(1194, 834)),
    ]) {
      testWidgets('$name lays out without overflow', (tester) async {
        await boot(
          tester,
          size: size,
          closet: const [
            WardrobeItem(id: 'w1', title: 'Black dress', category: 'dresses'),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(WtmStoryRail), findsOneWidget);
        expect(find.byType(WtmProductCard), findsWidgets);

        await scrollToEnd(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(WtmProductCard), findsWidgets);
      });
    }

    for (final scale in const [1.3, 2.0]) {
      testWidgets('${scale}x text on a small phone does not clip', (
        tester,
      ) async {
        await boot(
          tester,
          size: const Size(320, 640),
          textScale: scale,
          closet: const [
            WardrobeItem(id: 'w1', title: 'Black dress', category: 'dresses'),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(WtmStoryRail), findsOneWidget);

        await scrollToEnd(tester);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the bottom navigation never sits over feed content', (
      tester,
    ) async {
      await boot(tester, size: const Size(430, 932), productCount: 12);
      await scrollToEnd(tester);

      final navTop = tester.getTopLeft(find.byType(WtmBottomNav)).dy;
      final cards = find.byType(WtmProductCard).evaluate().toList();
      expect(cards, isNotEmpty);
      for (final element in cards) {
        final box = element.renderObject! as RenderBox;
        final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
        expect(
          bottom,
          lessThanOrEqualTo(navTop),
          reason: 'a product card is behind the bottom navigation',
        );
      }
    });
  });

  group('fallbacks', () {
    testWidgets('shopping OFF leaves Discover standing, with no products', (
      tester,
    ) async {
      // Two independent kill switches: the catalog can go without the rail.
      await boot(tester, size: const Size(430, 4200), shopping: false);

      expect(find.byType(WtmStoryRail), findsOneWidget);
      expect(find.byType(WtmDailyPulse), findsOneWidget);
      expect(find.byType(WtmDiscoverProductRow), findsNothing);
      expect(find.byType(WtmProductCard), findsNothing);
    });

    testWidgets('an empty catalog invites rather than blanking', (
      tester,
    ) async {
      await boot(tester, productCount: 0);

      expect(find.byType(WtmProductStrip), findsNothing);
      expect(find.text('Start with a few picks'), findsOneWidget);
      // The rest of Discover is still there — an empty catalog is not an empty
      // screen (§24).
      expect(find.byType(WtmStoryRail), findsOneWidget);
    });

    testWidgets('a catalog failure keeps the rail and offers retry', (
      tester,
    ) async {
      await boot(tester, catalogFails: true);

      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.byType(WtmStoryRail), findsOneWidget);
      expect(find.byType(WtmDailyPulse), findsOneWidget);
    });

    testWidgets('nothing at all still shows the mood module, not a blank', (
      tester,
    ) async {
      await boot(
        tester,
        shopping: false,
        giveaways: false,
        offers: false,
        news: false,
      );

      expect(find.byType(WtmEmptyState), findsOneWidget);
      expect(find.byType(WtmDailyPulse), findsOneWidget);
    });
  });
}
