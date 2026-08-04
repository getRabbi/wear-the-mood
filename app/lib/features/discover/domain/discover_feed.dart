import 'package:flutter/foundation.dart';

import '../../../data/models/product.dart';
import '../../../data/models/wardrobe_item.dart';
import 'discover_story.dart';

/// One row of the Discover feed (DISCOVER spec §16).
///
/// A sealed hierarchy rather than a map with a `type` string: the renderer
/// switches exhaustively, so adding a variant is a compile error at every
/// place that has to handle it instead of a blank row discovered in QA. And
/// nothing infers a row's kind from its title (§16 is explicit about that).
@immutable
sealed class DiscoverFeedItem {
  const DiscoverFeedItem();

  /// Stable across rebuilds — this is the widget key, so a churning value
  /// would throw away scroll position and image cache on every refresh (§23).
  String get key;
}

/// A pair of product cards forming one grid row on a phone.
///
/// Rows rather than loose products because the feed is a single scrolling list
/// with full-width modules interleaved; a real grid cannot interleave, and two
/// nested scrollables fight each other (§15 "no multiple nested scroll views
/// with conflicting physics").
final class ProductRowItem extends DiscoverFeedItem {
  const ProductRowItem(this.products);

  final List<Product> products;

  @override
  String get key => 'row:${products.map((p) => p.id).join(':')}';
}

/// `COMPLETE YOUR LOOK` — one owned closet item plus matching products (§9.1).
final class CompleteLookItem extends DiscoverFeedItem {
  const CompleteLookItem({required this.anchor, required this.suggestions});

  /// Something the user already owns. Never a purchase suggestion dressed up
  /// as one — the module's whole point is starting from their wardrobe.
  final WardrobeItem anchor;
  final List<Product> suggestions;

  @override
  String get key => 'look:${anchor.id}';
}

/// A Giveaway, Offer or Newsroom module, rendered from the same story the rail
/// uses so there is one source of truth for that content.
final class StoryModuleItem extends DiscoverFeedItem {
  const StoryModuleItem(this.story);

  final DiscoverStory story;

  @override
  String get key => 'module:${story.id}:${story.contentVersion}';
}

/// Composes the Discover feed (§8.3).
abstract final class DiscoverFeedComposer {
  /// Products between two full-width modules.
  static const productsPerBlock = 4;

  /// Phone grid width. The renderer overrides it on a tablet.
  static const columns = 2;

  /// Builds the feed.
  ///
  /// The rhythm is four product cards, then at most ONE full-width module,
  /// repeating. That single rule is what keeps Discover from reading as a
  /// marketplace (§8.3, §26.13).
  ///
  /// [railStoryIds] are the stories already shown in the rail above. They are
  /// excluded from the first module slot so the same campaign does not appear
  /// twice in one viewport (§33.3 deduplication).
  ///
  /// Modules are consumed in the order given and simply run out; when there
  /// are none left the feed continues as products. An unavailable module is
  /// never rendered as an empty section (§8.3, §26.15).
  static List<DiscoverFeedItem> compose({
    required List<Product> products,
    List<DiscoverStory> modules = const [],
    CompleteLookItem? completeLook,
    Set<String> railStoryIds = const {},
    int columns = columns,
  }) {
    final items = <DiscoverFeedItem>[];

    // Complete Your Look leads when it exists: it is the retention module, and
    // it is about something the user already owns rather than something to buy.
    final queue = <DiscoverFeedItem>[
      if (completeLook != null && completeLook.suggestions.isNotEmpty)
        completeLook,
      for (final story in modules)
        if (!railStoryIds.contains(story.id)) StoryModuleItem(story),
    ];

    var moduleIndex = 0;
    for (var i = 0; i < products.length; i += columns) {
      items.add(
        ProductRowItem(
          products.sublist(i, (i + columns).clamp(0, products.length)),
        ),
      );

      // A module goes in only on a completed block — a half-finished row of
      // products followed by a banner reads as a mistake.
      final shown = i + columns;
      final onBoundary = shown % productsPerBlock == 0;
      if (onBoundary &&
          shown <= products.length &&
          moduleIndex < queue.length) {
        items.add(queue[moduleIndex++]);
      }
    }

    return items;
  }

  /// Picks the closet item and the products to pair with it (§9.1).
  ///
  /// Deterministic and explainable: anchor on a garment the user owns, then
  /// suggest products from DIFFERENT categories, because "your black dress +
  /// another black dress" is not completing a look. Returns null rather than a
  /// weak module — an empty or nonsensical suggestion set is worse than no
  /// module at all (§26.15).
  static CompleteLookItem? completeLook({
    required List<WardrobeItem> closet,
    required List<Product> products,
    int maxSuggestions = 3,
  }) {
    if (closet.isEmpty || products.isEmpty) return null;

    final anchor = closet.firstWhere(
      (item) => (item.category ?? '').trim().isNotEmpty,
      orElse: () => closet.first,
    );
    final anchorCategory = (anchor.category ?? '').trim().toLowerCase();

    final suggestions = <Product>[];
    final usedCategories = <String>{
      if (anchorCategory.isNotEmpty) anchorCategory,
    };
    for (final product in products) {
      final category = (product.category ?? '').trim().toLowerCase();
      if (category.isEmpty || usedCategories.contains(category)) continue;
      suggestions.add(product);
      usedCategories.add(category);
      if (suggestions.length >= maxSuggestions) break;
    }

    // Two is the minimum that reads as "completing" something.
    if (suggestions.length < 2) return null;
    return CompleteLookItem(anchor: anchor, suggestions: suggestions);
  }
}
