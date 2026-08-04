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
    DiscoverStory story(String id) => DiscoverStory(
      id: id,
      type: DiscoverStoryType.giveaway,
      category: 'GIVEAWAY',
      title: 'Free to a good home',
      destination: const DiscoverStoryDestination(route: AppRoute.wtmGiveaways),
    );

    List<Product> products(int count) => [
      for (var i = 0; i < count; i++) _product(id: 'p$i'),
    ];

    test('four product cards, then at most one module', () {
      // The single rule that keeps Discover from reading as a marketplace
      // (§8.3, §26.13).
      final items = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [story('s1'), story('s2')],
      );

      expect(items[0], isA<ProductRowItem>());
      expect(items[1], isA<ProductRowItem>());
      expect(items[2], isA<StoryModuleItem>());
      expect(items[3], isA<ProductRowItem>());
      expect(items[4], isA<ProductRowItem>());
      expect(items[5], isA<StoryModuleItem>());
    });

    test('never two modules in a row', () {
      final items = DiscoverFeedComposer.compose(
        products: products(12),
        modules: [story('s1'), story('s2'), story('s3')],
      );

      for (var i = 1; i < items.length; i++) {
        final consecutive =
            items[i] is! ProductRowItem && items[i - 1] is! ProductRowItem;
        expect(consecutive, isFalse, reason: 'two modules adjacent at $i');
      }
    });

    test('runs out of modules gracefully rather than repeating one', () {
      final items = DiscoverFeedComposer.compose(
        products: products(16),
        modules: [story('s1')],
      );
      expect(items.whereType<StoryModuleItem>(), hasLength(1));
    });

    test('no modules at all is just products, never an empty section', () {
      // §26.15: no empty modules.
      final items = DiscoverFeedComposer.compose(products: products(8));
      expect(items.every((i) => i is ProductRowItem), isTrue);
    });

    test('a story already in the rail is not repeated in the first module', () {
      // §33.3: the same campaign must not appear twice in one viewport.
      final items = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [story('rail-story'), story('other')],
        railStoryIds: {'rail-story'},
      );

      final modules = items.whereType<StoryModuleItem>().toList();
      expect(modules.map((m) => m.story.id), ['other']);
    });

    test('rows respect the column count, with an odd tail', () {
      final items = DiscoverFeedComposer.compose(products: products(5));
      final rows = items.whereType<ProductRowItem>().toList();
      expect(rows.map((r) => r.products.length), [2, 2, 1]);
    });

    test('three columns on a tablet', () {
      final items = DiscoverFeedComposer.compose(
        products: products(6),
        columns: 3,
      );
      final rows = items.whereType<ProductRowItem>().toList();
      expect(rows.map((r) => r.products.length), [3, 3]);
    });

    test('item keys are stable and unique', () {
      // Feed items are widget keys; a duplicate is a hard crash and a churning
      // one throws away scroll position (§23).
      final items = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [story('s1')],
      );
      final keys = items.map((i) => i.key).toList();
      expect(keys.toSet(), hasLength(keys.length));

      final again = DiscoverFeedComposer.compose(
        products: products(8),
        modules: [story('s1')],
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
        completeLook: DiscoverFeedComposer.completeLook(
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
