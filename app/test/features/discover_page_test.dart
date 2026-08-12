import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/router/routes.dart';
import 'package:app/data/models/money.dart';
import 'package:app/data/models/product.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/features/discover/domain/discover_page.dart';
import 'package:app/features/discover/domain/discover_story.dart';

/// The approved Discover composition, as rules rather than pixels.
///
/// Every defect that got the previous build rejected was a COMPOSITION defect —
/// Complete Your Look three times, "Keep exploring" four times, product after
/// product with nothing between them. Those are decided in one pure function,
/// so this is where they are pinned down: no widget, no pump, no flake.

Product _product(
  String id, {
  String? category = 'dresses',
  bool sold = false,
}) => Product(
  id: id,
  merchant: const MerchantSummary(id: 'm1', name: 'Studio Label'),
  title: 'Piece $id',
  category: category,
  price: const Money(amountMinor: 349900, currency: 'BDT'),
  stockStatus: sold ? StockStatus.outOfStock : StockStatus.inStock,
);

List<Product> _products(int count) => [
  for (var i = 0; i < count; i++)
    // Rotating categories, so Complete Your Look has different things to pair.
    _product('p$i', category: ['tops', 'bottoms', 'shoes', 'bags'][i % 4]),
];

WardrobeItem _owned(String id, {String? title = 'Noir blouse'}) =>
    WardrobeItem(id: id, title: title, category: 'dresses');

DiscoverStory _story(DiscoverStoryType type, {String? id}) => DiscoverStory(
  id: id ?? type.name,
  type: type,
  category: type.name.toUpperCase(),
  title: 'Story ${type.name}',
  destination: const DiscoverStoryDestination(route: AppRoute.wtmGiveaways),
);

/// The six-card rail the approved layout asks for.
List<DiscoverStory> _fullRail() => [
  for (final type in DiscoverStoryType.values) _story(type),
];

List<T> _sectionsOf<T>(DiscoverPageLayout layout) =>
    layout.sections.whereType<T>().toList();

void main() {
  group('section order', () {
    test('is the approved sequence, top to bottom', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );

      expect(layout.sections.map((s) => s.runtimeType.toString()).toList(), [
        'StoryRailSection',
        'MoodPulseSection',
        'ProductRowSection', // Picked for You
        'CompleteLookSection',
        'CampaignSection',
        'NewsroomSection',
        'ProductRowSection', // New for your mood
      ]);
    });

    test('the Story rail is the first content section', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      expect(layout.sections.first, isA<StoryRailSection>());
    });

    test('the one interaction card sits above the first product row', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      final pulse = layout.sections.indexWhere((s) => s is MoodPulseSection);
      final row = layout.sections.indexWhere((s) => s is ProductRowSection);
      expect(pulse, lessThan(row));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });

    test('a rail under two cards is not a rail', () {
      // One eligible story: the screen shows the compact fallback card, so the
      // composer must not claim a rail section.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.newsroom)],
        products: _products(8),
      );
      expect(_sectionsOf<StoryRailSection>(layout), isEmpty);
    });
  });

  group('repetition rules', () {
    test('Complete Your Look appears exactly once, however big the closet', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [
          for (var i = 0; i < 6; i++) _owned('w$i', title: 'Garment $i'),
        ],
      );
      expect(_sectionsOf<CompleteLookSection>(layout), hasLength(1));
    });

    test('one campaign card only, and a giveaway outranks an offer', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.giveaway),
          _story(DiscoverStoryType.offer),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      final campaigns = _sectionsOf<CampaignSection>(layout);
      expect(campaigns, hasLength(1));
      expect(campaigns.single.story!.type, DiscoverStoryType.giveaway);
    });

    test('an offer takes the campaign slot when no giveaway is live', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.offer),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      expect(
        _sectionsOf<CampaignSection>(layout).single.story!.type,
        DiscoverStoryType.offer,
      );
    });

    test('the Newsroom card appears exactly once', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<NewsroomSection>(layout), hasLength(1));
    });

    test('no row heading is ever used twice', () {
      // 24 products is six full rows — every slot the page has. If any heading
      // repeated, this is where "Keep exploring" ×4 would come back.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(40),
        closet: [_owned('w1')],
      );
      final slots = _sectionsOf<ProductRowSection>(
        layout,
      ).map((r) => r.slot).toList();
      expect(slots.toSet(), hasLength(slots.length));
    });

    test('the page ends after two rows, however big the catalog', () {
      // 200 products used to become row after row down an endless tail. The
      // approved layout has exactly two strips; the rest lives behind View all.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(200),
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      expect(layout.rowsRendered, 2);
      // And the LAST thing on the page is that second row.
      expect(layout.sections.last, isA<ProductRowSection>());
      expect(
        (layout.sections.last as ProductRowSection).slot,
        DiscoverRowSlot.newForYourMood,
      );
    });

    test('nothing follows the Newsroom card except one row', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(60),
        closet: [_owned('w1')],
      );
      final news = layout.sections.indexWhere((s) => s is NewsroomSection);
      expect(news, greaterThan(-1));
      final after = layout.sections.sublist(news + 1);
      expect(after, hasLength(1));
      expect(after.single, isA<ProductRowSection>());
    });
  });

  group('deduplication', () {
    test('a product id is never placed twice on one page', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(24),
        closet: [_owned('w1')],
      );

      final placed = <String>[
        for (final row in _sectionsOf<ProductRowSection>(layout))
          ...row.products.map((p) => p.id),
        for (final look in _sectionsOf<CompleteLookSection>(layout))
          ...look.look.suggestions.map((p) => p.id),
      ];
      expect(placed.toSet(), hasLength(placed.length));
      expect(layout.usedProductIds, placed.toSet());
    });

    test(
      'Complete Your Look pairs products the lead row did not already use',
      () {
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(12),
          closet: [_owned('w1')],
        );
        final lead = _sectionsOf<ProductRowSection>(layout).first;
        final look = _sectionsOf<CompleteLookSection>(layout).single;
        expect(
          look.look.suggestions
              .map((p) => p.id)
              .toSet()
              .intersection(lead.products.map((p) => p.id).toSet()),
          isEmpty,
        );
      },
    );

    test('a collapsed rail hands its story to the card, not to both', () {
      // Caught on device: with only a Newsroom item live, the compact fallback
      // card AND the feed's editorial card showed the same Style Note. The
      // editorial card is the fuller telling, so it keeps the story and the
      // compact card stands down.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.newsroom)],
        products: _products(8),
      );
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNotNull);
      expect(layout.fallbackStory, isNull);
    });

    test('a lone personalized story still gets the compact card', () {
      // Nothing below would show a Closet Match, so dropping the compact card
      // here would lose the story altogether.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.closetMatch)],
        products: _products(8),
      );
      expect(layout.fallbackStory?.type, DiscoverStoryType.closetMatch);
    });

    test('with shopping off, a lone campaign story keeps the compact card', () {
      // No editorial slot renders at all, so the compact card is the only place
      // left for it.
      final layout = DiscoverPage.compose(
        stories: [_story(DiscoverStoryType.giveaway)],
        products: _products(8),
        shoppingEnabled: false,
      );
      expect(layout.fallbackStory?.type, DiscoverStoryType.giveaway);
    });
  });

  group('density', () {
    test('a row never holds more than four products', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(40),
        closet: [_owned('w1')],
      );
      for (final row in _sectionsOf<ProductRowSection>(layout)) {
        expect(
          row.products,
          hasLength(lessThanOrEqualTo(DiscoverPage.productsPerRow)),
        );
      }
    });

    test('two rows never sit back to back while a module could separate', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
      );
      for (var i = 1; i < layout.sections.length; i++) {
        if (layout.sections[i] is! ProductRowSection) continue;
        expect(
          layout.sections[i - 1],
          isNot(isA<ProductRowSection>()),
          reason: 'two product rows in a row is the catalog wall returning',
        );
      }
    });

    test('the fixed editorial slots separate the rows even when empty', () {
      // No closet, no campaign, no article — yet the two editorial cards still
      // hold their slots, so the closing row is never stacked straight onto the
      // lead row. That is the second thing those fixed slots buy: a stable
      // rhythm rather than two strips running together on a quiet day.
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.dailyEdit),
          _story(DiscoverStoryType.closetMatch),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<ProductRowSection>(layout), hasLength(2));
      for (var i = 1; i < layout.sections.length; i++) {
        if (layout.sections[i] is! ProductRowSection) continue;
        expect(layout.sections[i - 1], isNot(isA<ProductRowSection>()));
      }
    });
  });

  group('empty modules are omitted, never rendered blank', () {
    test('an empty closet contributes no Complete Your Look', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
      );
      expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
    });

    test('no campaign story still keeps the card, holding its slot', () {
      // The two editorial slots are fixed furniture: they hold their place so
      // the page does not reshuffle when a campaign starts or ends, and so
      // Giveaways keeps an entry point on this surface. Empty means an
      // invitation, never an invented campaign — the null story is what makes
      // that distinction impossible to lose.
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.newForYou),
          _story(DiscoverStoryType.newsroom),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<CampaignSection>(layout).single.story, isNull);
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNotNull);
    });

    test('both editorial cards render with nothing live at all', () {
      final layout = DiscoverPage.compose(
        stories: [
          _story(DiscoverStoryType.dailyEdit),
          _story(DiscoverStoryType.closetMatch),
        ],
        products: _products(8),
      );
      expect(_sectionsOf<CampaignSection>(layout).single.story, isNull);
      expect(_sectionsOf<NewsroomSection>(layout).single.story, isNull);
    });

    test('an empty catalog contributes no rows at all', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: const [],
        closet: [_owned('w1')],
      );
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
    });
  });

  group('the two kill switches', () {
    test('stories off drops the rail and keeps the rest', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
        storiesEnabled: false,
      );
      expect(_sectionsOf<StoryRailSection>(layout), isEmpty);
      expect(_sectionsOf<ProductRowSection>(layout), isNotEmpty);
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });

    test('shopping off leaves the rail and the interaction standing', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(8),
        closet: [_owned('w1')],
        shoppingEnabled: false,
      );
      expect(_sectionsOf<StoryRailSection>(layout), hasLength(1));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      // The whole commerce half goes with the flag, editorial cards included —
      // that is what the flag meant before this composer existed.
      expect(_sectionsOf<CampaignSection>(layout), isEmpty);
      expect(_sectionsOf<NewsroomSection>(layout), isEmpty);
    });
  });

  group('inventory: no avoidable holes, no invented content', () {
    // The five-product production catalog. It used to compose as a row of four
    // and then a closing row holding ONE card — "products disappear further
    // down Discover" — because the lead row filled greedily and whatever came
    // after made do with the remainder.
    test('a five-product catalog no longer strands a single card', () {
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: _products(5),
        closet: const [],
      );
      final rows = _sectionsOf<ProductRowSection>(layout);
      expect(rows, hasLength(2));
      expect(rows.first.products, hasLength(3));
      expect(rows.last.products, hasLength(2));
      for (final row in rows) {
        expect(
          row.products.length,
          greaterThanOrEqualTo(DiscoverPage.minProductsPerRow),
          reason: 'a row below the minimum is the stranded-card defect',
        );
      }
    });

    test(
      'every product placed exactly once — no duplication to fill a row',
      () {
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(5),
          closet: const [],
        );
        final placed = [
          for (final row in _sectionsOf<ProductRowSection>(layout))
            ...row.products.map((p) => p.id),
        ];
        expect(placed.toSet(), hasLength(placed.length));
        expect(placed.length, lessThanOrEqualTo(5));
      },
    );

    test('a full catalog is unchanged: both rows at the ceiling', () {
      final rows = _sectionsOf<ProductRowSection>(
        DiscoverPage.compose(
          stories: _fullRail(),
          products: _products(20),
          closet: const [],
        ),
      );
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.products.length),
        everyElement(DiscoverPage.productsPerRow),
      );
    });

    test(
      'four products still read as one full row, with nothing left over',
      () {
        final rows = _sectionsOf<ProductRowSection>(
          DiscoverPage.compose(
            stories: _fullRail(),
            products: _products(4),
            closet: const [],
          ),
        );
        expect(rows, hasLength(1));
        expect(rows.single.products, hasLength(4));
      },
    );

    test('the lead-row rule, stated directly', () {
      // Fill the row unless the remainder could not stand on its own.
      expect(DiscoverPage.leadRowSize(0), 0);
      expect(DiscoverPage.leadRowSize(1), 1); // the only row it will ever have
      expect(DiscoverPage.leadRowSize(2), 2);
      expect(DiscoverPage.leadRowSize(4), 4); // remainder 0 — nothing stranded
      expect(DiscoverPage.leadRowSize(5), 3); // was 4, stranding one
      expect(DiscoverPage.leadRowSize(6), 4);
      expect(DiscoverPage.leadRowSize(9), 4);
    });

    test(
      'a module that declines hands its inventory back to the closing row',
      () {
        // Complete Your Look needs two DIFFERENT categories to say anything
        // real. Given products that are all one category it returns nothing —
        // and the products it did not take must not vanish with it.
        final products = [
          for (var i = 0; i < 6; i++) _product('p$i', category: 'tops'),
        ];
        final layout = DiscoverPage.compose(
          stories: _fullRail(),
          products: products,
          closet: [_owned('w1')],
        );
        expect(_sectionsOf<CompleteLookSection>(layout), isEmpty);
        expect(
          layout.usedProductIds,
          hasLength(6),
          reason: 'nothing may be left behind by a module that stood down',
        );
      },
    );

    test('an exhausted catalog does not blank the editorial slots', () {
      // One source running dry must not take the rest of the page with it.
      final layout = DiscoverPage.compose(
        stories: _fullRail(),
        products: const [],
        closet: const [],
      );
      expect(_sectionsOf<ProductRowSection>(layout), isEmpty);
      expect(_sectionsOf<CampaignSection>(layout), hasLength(1));
      expect(_sectionsOf<NewsroomSection>(layout), hasLength(1));
      expect(_sectionsOf<MoodPulseSection>(layout), hasLength(1));
    });
  });

  group('the pool feeds the editorial slots, the rail only shows six', () {
    test('a rail full of one kind cannot empty the Newsroom card', () {
      // The regression this guards: giveaways rank above the newsroom, so once
      // a source could contribute several cards, six giveaways filled the rail
      // and the Newsroom card below it claimed there was nothing to read — on
      // an account with thousands of articles.
      final pool = <DiscoverStory>[
        for (var i = 0; i < 7; i++)
          _story(DiscoverStoryType.giveaway, id: 'g$i'),
        _story(DiscoverStoryType.newsroom, id: 'n1'),
      ];
      final layout = DiscoverPage.compose(
        stories: pool,
        products: _products(8),
        closet: const [],
      );

      final rail = _sectionsOf<StoryRailSection>(layout).single;
      expect(rail.stories, hasLength(DiscoverRail.maxCards));
      expect(
        rail.stories.every((s) => s.type == DiscoverStoryType.giveaway),
        isTrue,
      );
      expect(
        _sectionsOf<NewsroomSection>(layout).single.story?.id,
        'n1',
        reason: 'the card chooses from the POOL, not from the visible rail',
      );
    });

    test('the rail is a prefix of the pool — no reshuffle', () {
      final pool = <DiscoverStory>[
        for (var i = 0; i < 9; i++)
          _story(DiscoverStoryType.newsroom, id: 'n$i'),
      ];
      final rail = _sectionsOf<StoryRailSection>(
        DiscoverPage.compose(
          stories: pool,
          products: const [],
          closet: const [],
        ),
      ).single;
      expect(
        rail.stories.map((s) => s.id).toList(),
        pool.take(DiscoverRail.maxCards).map((s) => s.id).toList(),
      );
    });
  });
}
