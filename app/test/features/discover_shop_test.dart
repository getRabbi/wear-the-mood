import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/discover/domain/discover_feed.dart';
import 'package:app/features/discover/domain/discover_story.dart';
import 'package:app/features/discover/domain/product_filters.dart';
import 'package:app/core/router/routes.dart';

/// Phase 3 domain rules: money, product state, feed rhythm and filters — all
/// pure, so the parts a wrong answer would quietly corrupt (a price, a
/// discount, a feed that reads as a marketplace) are tested without a widget.

Product _product({
  String id = 'p1',
  int priceMinor = 349900,
  int? originalMinor,
  String currency = 'BDT',
  String? category = 'dresses',
  TryOnStatus tryOn = TryOnStatus.unsupported,
  StockStatus stock = StockStatus.inStock,
  DateTime? syncedAt,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Black silk dress',
  category: category,
  price: Money(amountMinor: priceMinor, currency: currency),
  originalPrice: originalMinor == null
      ? null
      : Money(amountMinor: originalMinor, currency: currency),
  tryOnStatus: tryOn,
  stockStatus: stock,
  lastSyncedAt: syncedAt,
);

void main() {
  group('money', () {
    test('is integer minor units, never a float', () {
      const price = Money(amountMinor: 349900, currency: 'BDT');
      expect(price.amountMinor, isA<int>());
      expect(price.amountMinor, 349900);
    });

    test('round-trips through JSON without losing a unit', () {
      // The whole reason minor units exist: a double would not survive this
      // exactly for every value.
      for (final amount in [0, 1, 99, 100, 349900, 999999999]) {
        final money = Money(amountMinor: amount, currency: 'USD');
        expect(Money.fromJson(money.toJson()).amountMinor, amount);
      }
    });

    test('formats with the currency\'s own decimal places', () {
      // JPY has none; rendering ¥1000 as ¥10.00 would be a factor-100 lie.
      expect(
        const Money(amountMinor: 1000, currency: 'JPY').format(locale: 'en'),
        contains('1,000'),
      );
      expect(
        const Money(amountMinor: 1000, currency: 'USD').format(locale: 'en'),
        contains('10'),
      );
    });

    test('falls back rather than throwing on an unknown currency', () {
      // A product card must not crash because a merchant sent a code intl
      // does not know.
      final formatted = const Money(
        amountMinor: 1234,
        currency: 'ZZZ',
      ).format();
      expect(formatted, isNotEmpty);
    });

    test('a discount must be a real reduction in the SAME currency', () {
      const price = Money(amountMinor: 100, currency: 'BDT');
      expect(
        price.isDiscountFrom(const Money(amountMinor: 200, currency: 'BDT')),
        isTrue,
      );
      expect(
        price.isDiscountFrom(const Money(amountMinor: 100, currency: 'BDT')),
        isFalse,
      );
      expect(
        price.isDiscountFrom(const Money(amountMinor: 50, currency: 'BDT')),
        isFalse,
      );
      // Comparing across currencies without conversion is meaningless, so it
      // is "no discount" rather than a number invented from two incomparable
      // amounts (§26.10).
      expect(
        price.isDiscountFrom(const Money(amountMinor: 200, currency: 'USD')),
        isFalse,
      );
      expect(price.isDiscountFrom(null), isFalse);
    });

    test('discount percent is null when there is no discount', () {
      const price = Money(amountMinor: 100, currency: 'BDT');
      expect(
        price.discountPercentFrom(
          const Money(amountMinor: 200, currency: 'BDT'),
        ),
        50,
      );
      expect(
        price.discountPercentFrom(
          const Money(amountMinor: 100, currency: 'BDT'),
        ),
        isNull,
      );
      expect(price.discountPercentFrom(null), isNull);
    });
  });

  group('product state', () {
    test('pending try-on is NOT try-on ready', () {
      // §35: never label a product Try-On Ready until compatibility passes.
      expect(_product(tryOn: TryOnStatus.ready).isTryOnReady, isTrue);
      expect(_product(tryOn: TryOnStatus.pending).isTryOnReady, isFalse);
      expect(_product(tryOn: TryOnStatus.unsupported).isTryOnReady, isFalse);
      expect(_product(tryOn: TryOnStatus.unknown).isTryOnReady, isFalse);
    });

    test('an unrecognised enum from a newer backend degrades safely', () {
      // §37.4: unknown data must not crash the feed. Built as a literal wire
      // map rather than round-tripped through toJson, because this is exactly
      // the payload shape a newer server would actually send.
      final parsed = Product.fromJson({
        'id': 'p1',
        'merchant': {'id': 'm1', 'name': 'Studio Label'},
        'title': 'Black silk dress',
        'price': {'amount_minor': 349900, 'currency': 'BDT'},
        'try_on_status': 'holographic',
        'stock_status': 'teleporting',
        'match_reason': 'vibes',
        // A field this build has never heard of must simply be ignored.
        'hologram_ready': true,
      });

      expect(parsed.tryOnStatus, TryOnStatus.unknown);
      expect(parsed.stockStatus, StockStatus.unknown);
      expect(parsed.matchReason, MatchReason.unknown);
      expect(parsed.isTryOnReady, isFalse);
      expect(parsed.price.amountMinor, 349900);
    });

    test('parses a full wire payload', () {
      final parsed = Product.fromJson({
        'id': 'p1',
        'merchant': {'id': 'm1', 'name': 'Studio Label', 'logo_url': null},
        'title': 'Black silk dress',
        'brand': 'Studio',
        'price': {'amount_minor': 349900, 'currency': 'BDT'},
        'original_price': {'amount_minor': 499900, 'currency': 'BDT'},
        'image_urls': ['https://cdn.test/a.jpg'],
        'image_focal_x': 0.5,
        'image_focal_y': 0.35,
        'stock_status': 'in_stock',
        'try_on_status': 'ready',
        'match_reason': 'closet_match',
        'saved': true,
        'tracking_token': 'p:p1',
      });

      expect(parsed.merchant.name, 'Studio Label');
      expect(parsed.isDiscounted, isTrue);
      expect(parsed.discountPercent, 30);
      expect(parsed.matchReason, MatchReason.closetMatch);
      expect(parsed.isTryOnReady, isTrue);
      expect(parsed.saved, isTrue);
      // The wire never carries an affiliate URL (§18, safety rule 11).
      expect(parsed.toString(), isNot(contains('affiliate')));
    });

    test('staleness is measured against the last confirmed sync', () {
      final now = DateTime(2026, 8, 5);
      expect(
        _product(
          syncedAt: now.subtract(const Duration(hours: 6)),
        ).isStaleAt(now),
        isFalse,
      );
      expect(
        _product(
          syncedAt: now.subtract(const Duration(days: 5)),
        ).isStaleAt(now),
        isTrue,
      );
      // Never synced at all is not a claim we can qualify — the server
      // suppresses those before they reach the client.
      expect(_product().isStaleAt(now), isFalse);
    });
  });

  group('feed rhythm', () {
    DiscoverStory story(
      String id, {
      DiscoverStoryType type = DiscoverStoryType.giveaway,
    }) => DiscoverStory(
      id: id,
      type: type,
      category: 'GIVEAWAY',
      title: 'Free to a good home',
      destination: const DiscoverStoryDestination(route: AppRoute.wtmGiveaways),
    );

    List<Product> products(int count) => [
      for (var i = 0; i < count; i++) _product(id: 'p$i'),
    ];

    final giveaway = story('s-give');
    final offer = story('s-offer', type: DiscoverStoryType.offer);
    final news = story('s-news', type: DiscoverStoryType.newsroom);

    test(
      'the approved order: strip, then the mixed modules, then products',
      () {
        // The layout the prototype fixes: one curated band, the retention
        // module, the campaign card, the read — and only then more products.
        final items = DiscoverFeedComposer.compose(
          products: products(8),
          modules: [giveaway, offer, news],
          completeLooks: [
            CompleteLookItem(
              anchor: const WardrobeItem(id: 'w1', category: 'dresses'),
              suggestions: products(2),
            ),
          ],
        );

        expect(items[0], isA<ProductStripItem>());
        expect(items[1], isA<CompleteLookItem>());
        expect(
          (items[2] as StoryModuleItem).story.type,
          DiscoverStoryType.giveaway,
        );
        expect(
          (items[3] as StoryModuleItem).story.type,
          DiscoverStoryType.newsroom,
        );
        expect(items[4], isA<ProductStripItem>());
        expect(
          (items[4] as ProductStripItem).slot,
          DiscoverStripSlot.moreForYou,
        );
      },
    );

    test('never more than four product cards in one band', () {
      // The rule that keeps Discover from reading as a marketplace wall.
      final items = DiscoverFeedComposer.compose(
        products: products(23),
        modules: [giveaway, news],
      );
      for (final strip in items.whereType<ProductStripItem>()) {
        expect(
          strip.products.length,
          lessThanOrEqualTo(DiscoverFeedComposer.productsPerStrip),
        );
      }
      // And every product in the page is still reachable — capping the band
      // must not silently drop stock.
      expect(
        items
            .whereType<ProductStripItem>()
            .expand((s) => s.products)
            .map((p) => p.id)
            .toList(),
        products(23).map((p) => p.id).toList(),
      );
    });

    test('an offer stands in when no giveaway is live', () {
      final items = DiscoverFeedComposer.compose(
        products: products(4),
        modules: [offer, news],
      );
      final modules = items.whereType<StoryModuleItem>().toList();
      expect(modules.first.story.type, DiscoverStoryType.offer);
    });

    test('one campaign card and one read, never the rail again', () {
      // The approved layout carries exactly one Giveaway/Offer card and one
      // Newsroom card. The offer stays in the rail rather than becoming a
      // second campaign banner further down the feed.
      final items = DiscoverFeedComposer.compose(
        products: products(12),
        modules: [giveaway, offer, news],
      );
      final types = items
          .whereType<StoryModuleItem>()
          .map((m) => m.story.type)
          .toList();
      expect(types, [DiscoverStoryType.giveaway, DiscoverStoryType.newsroom]);
    });

    test('runs out of modules gracefully rather than repeating one', () {
      final items = DiscoverFeedComposer.compose(
        products: products(16),
        modules: [giveaway],
      );
      expect(items.whereType<StoryModuleItem>(), hasLength(1));
    });

    test('no modules at all is just bands, never an empty section', () {
      // §26.15: no empty modules.
      final items = DiscoverFeedComposer.compose(products: products(8));
      expect(items.every((i) => i is ProductStripItem), isTrue);
    });

    test('bands fill to four, with a short tail band', () {
      final items = DiscoverFeedComposer.compose(products: products(9));
      final strips = items.whereType<ProductStripItem>().toList();
      expect(strips.map((s) => s.products.length), [4, 4, 1]);
      expect(strips.map((s) => s.slot), [
        DiscoverStripSlot.pickedForYou,
        DiscoverStripSlot.moreForYou,
        DiscoverStripSlot.keepExploring,
      ]);
    });

    test('an empty page composes to nothing, not to an empty band', () {
      expect(
        DiscoverFeedComposer.compose(
          products: const [],
          modules: [giveaway, news],
        ),
        isEmpty,
      );
    });

    test('item keys are stable and unique', () {
      // Feed items are widget keys; a duplicate is a hard crash and a churning
      // one throws away scroll position (§23).
      final items = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [giveaway],
      );
      final keys = items.map((i) => i.key).toList();
      expect(keys.toSet(), hasLength(keys.length));

      final again = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [giveaway],
      );
      expect(again.map((i) => i.key), keys);
    });
  });

  group('complete your look', () {
    WardrobeItem garment(String id, String? category) =>
        WardrobeItem(id: id, title: 'Black dress', category: category);

    test('suggests different categories, never more of the same thing', () {
      final module = DiscoverFeedComposer.completeLook(
        closet: [garment('w1', 'dresses')],
        products: [
          _product(id: 'p1', category: 'dresses'),
          _product(id: 'p2', category: 'shoes'),
          _product(id: 'p3', category: 'bags'),
          _product(id: 'p4', category: 'shoes'),
        ],
      );

      expect(module, isNotNull);
      expect(module!.anchor.id, 'w1');
      // Another dress does not complete a look, and neither does a second
      // pair of shoes.
      expect(module.suggestions.map((p) => p.category), ['shoes', 'bags']);
    });

    test('is skipped rather than shown weak', () {
      // §26.15: better no module than one with a single unrelated suggestion.
      expect(
        DiscoverFeedComposer.completeLook(
          closet: const [],
          products: [_product()],
        ),
        isNull,
      );
      expect(
        DiscoverFeedComposer.completeLook(
          closet: [garment('w1', 'dresses')],
          products: const [],
        ),
        isNull,
      );
      expect(
        DiscoverFeedComposer.completeLook(
          closet: [garment('w1', 'dresses')],
          products: [_product(id: 'p1', category: 'shoes')],
        ),
        isNull,
        reason: 'one suggestion does not read as completing a look',
      );
    });

    test('leads the feed when it exists', () {
      final items = DiscoverFeedComposer.compose(
        products: [
          for (var i = 0; i < 8; i++)
            _product(id: 'p$i', category: i.isEven ? 'shoes' : 'bags'),
        ],
        modules: [
          DiscoverStory(
            id: 's1',
            type: DiscoverStoryType.giveaway,
            category: 'GIVEAWAY',
            title: 'Free',
            destination: const DiscoverStoryDestination(
              route: AppRoute.wtmGiveaways,
            ),
          ),
        ],
        completeLooks: DiscoverFeedComposer.completeLooks(
          closet: [garment('w1', 'dresses')],
          products: [
            _product(id: 'p1', category: 'shoes'),
            _product(id: 'p2', category: 'bags'),
          ],
        ),
      );

      // The retention module comes before the promotional one.
      expect(items.whereType<CompleteLookItem>(), hasLength(1));
      final first = items.indexWhere((i) => i is CompleteLookItem);
      final second = items.indexWhere((i) => i is StoryModuleItem);
      expect(first, lessThan(second));
    });

    test('several anchors give several looks, each a different idea', () {
      // The tail breakers are real: distinct closet categories and distinct
      // suggested products, never the same module twice with a new title.
      final looks = DiscoverFeedComposer.completeLooks(
        closet: [
          garment('w1', 'dresses'),
          // A second dress is the same idea — it must not become a module.
          garment('w2', 'dresses'),
          garment('w3', 'coats'),
        ],
        products: [
          _product(id: 'p1', category: 'shoes'),
          _product(id: 'p2', category: 'bags'),
          _product(id: 'p3', category: 'jewellery'),
          _product(id: 'p4', category: 'shoes'),
          _product(id: 'p5', category: 'bags'),
        ],
      );

      expect(looks.map((l) => l.anchor.id), ['w1', 'w3']);
      final suggested = looks.expand((l) => l.suggestions).map((p) => p.id);
      expect(suggested.toSet(), hasLength(suggested.length));
    });

    test('an anchor with nothing to pair is skipped, not shown weak', () {
      expect(
        DiscoverFeedComposer.completeLooks(
          closet: [garment('w1', 'dresses')],
          products: [_product(id: 'p1', category: 'shoes')],
        ),
        isEmpty,
      );
      expect(
        DiscoverFeedComposer.completeLooks(
          closet: const [],
          products: [_product()],
        ),
        isEmpty,
      );
    });
  });

  group('filters', () {
    test('counts a price range as one filter', () {
      expect(const ProductFilters().activeCount, 0);
      expect(
        const ProductFilters(
          minPriceMinor: 0,
          maxPriceMinor: 500000,
        ).activeCount,
        1,
      );
      expect(
        const ProductFilters(
          category: 'Dresses',
          tryOnReady: true,
          colors: ['Black'],
        ).activeCount,
        3,
      );
    });

    test('a search term is not counted as a filter chip', () {
      // The indicator says `Filters · N`; a query is shown in the field, not
      // counted twice.
      const filters = ProductFilters(query: 'black dress');
      expect(filters.activeCount, 0);
      expect(filters.hasAny, isTrue);
    });

    test('is value-equal so an identical rebuild does not refetch', () {
      expect(
        const ProductFilters(category: 'Dresses', colors: ['Black']),
        const ProductFilters(category: 'Dresses', colors: ['Black']),
      );
      expect(
        const ProductFilters(category: 'Dresses').hashCode,
        const ProductFilters(category: 'Dresses').hashCode,
      );
    });

    test('clearing is explicit, never a null that means "unchanged"', () {
      const filters = ProductFilters(category: 'Dresses', minPriceMinor: 100);
      expect(filters.copyWith().category, 'Dresses');
      expect(filters.copyWith(clearCategory: true).category, isNull);
      expect(filters.copyWith(clearPrice: true).minPriceMinor, isNull);
    });
  });
}
