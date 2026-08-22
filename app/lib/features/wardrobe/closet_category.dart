import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';

/// A friendly display name for a piece even when its title is missing — falls
/// back to a capitalized category so the closet never shows a big plain
/// "Uncategorized" label (spec). Returns null only when there's nothing to show,
/// so callers can render a "Tap to categorize" chip instead.
String? closetItemName(WardrobeItem item) {
  final title = item.title?.trim();
  if (title != null && title.isNotEmpty) return title;
  final category = item.category?.trim();
  if (category != null && category.isNotEmpty) {
    return category[0].toUpperCase() + category.substring(1);
  }
  return null;
}

/// Best single-line label for an item card across Home and Closet (real-device
/// polish): the smart name ([closetItemName] — title, else capitalized
/// category), else the drawer the piece lives in, else a friendly "Needs
/// category". Never a big plain "Uncategorized". Keeps Home and the closet grid
/// in sync on one fallback chain.
String closetCardLabel(
  AppLocalizations l10n,
  WardrobeItem item, {
  String? drawerName,
}) {
  final name = closetItemName(item);
  if (name != null) return name;
  final drawer = drawerName?.trim();
  if (drawer != null && drawer.isNotEmpty) return drawer;
  return l10n.closetNeedsCategory;
}

/// Closet filter categories (redesign spec) — a DISPLAY grouping, never a
/// create/edit vocabulary.
///
/// The seven real filters group the twelve [GarmentCategory] values, and the
/// mapping is explicit and total: every one of the twelve belongs to exactly one
/// filter, and [_filterFor] is the single table that says which. `all` and
/// `favorites` are handled specially by the caller.
///
/// This used to be keyword matching over free text — "does the category contain
/// 'top'" — which is the same class of guess the whole category rework removed.
/// It was also wrong in both directions: `Hijab` and `Eyewear` matched no filter
/// at all and vanished from every chip, while `laptop bag` would have matched
/// tops if the substring check had ever seen it. An exact table cannot do either.
enum ClosetCategory {
  all,
  tops,
  bottoms,
  dresses,
  outerwear,
  shoes,
  bags,
  accessories,
  favorites,
}

extension ClosetCategoryX on ClosetCategory {
  String label(AppLocalizations l10n) => switch (this) {
    ClosetCategory.all => l10n.closetCatAll,
    ClosetCategory.tops => l10n.closetCatTops,
    ClosetCategory.bottoms => l10n.closetCatBottoms,
    ClosetCategory.dresses => l10n.closetCatDresses,
    ClosetCategory.outerwear => l10n.closetCatOuterwear,
    ClosetCategory.shoes => l10n.closetCatShoes,
    ClosetCategory.bags => l10n.closetCatBags,
    ClosetCategory.accessories => l10n.closetCatAccessories,
    ClosetCategory.favorites => l10n.closetCatFavorites,
  };

  /// The filter each of the twelve garment categories belongs to.
  ///
  /// Total by construction: `garment_category_test` asserts every value in
  /// [kGarmentCategories] appears here exactly once, so a thirteenth category
  /// added later cannot quietly become unfilterable.
  ///
  /// Everything worn on the head, face, wrist or waist groups under
  /// `accessories`, which is what a seven-chip row can express — the point of
  /// the twelve is that the RENDERER knows a hijab from a hat, not that the
  /// filter row needs six more chips. `Other` lands here too: it is the
  /// everything-else bucket, and leaving it out would make those pieces
  /// reachable only through "All".
  static const Map<String, ClosetCategory> _filterFor = {
    'tops': ClosetCategory.tops,
    'bottoms': ClosetCategory.bottoms,
    'dresses': ClosetCategory.dresses,
    'outerwear': ClosetCategory.outerwear,
    'shoes': ClosetCategory.shoes,
    'bags': ClosetCategory.bags,
    'hijab': ClosetCategory.accessories,
    'hats': ClosetCategory.accessories,
    'eyewear': ClosetCategory.accessories,
    'jewelry': ClosetCategory.accessories,
    'belts': ClosetCategory.accessories,
    'other': ClosetCategory.accessories,
  };

  /// The filter a stored category belongs to, or null when the value is not one
  /// of the twelve.
  ///
  /// Null is the honest answer for a legacy free-text value ("Party",
  /// "Activewear", something typed before the picker existed). Such an item
  /// stays fully visible under "All" and is offered a repair by the review
  /// banner; it is NOT guessed into a filter, because a guess here is a piece
  /// filed somewhere its owner did not put it.
  static ClosetCategory? filterFor(String? category) =>
      _filterFor[(category ?? '').trim().toLowerCase()];

  /// Whether a piece belongs under this filter chip.
  bool matches(String? category) {
    if (this == ClosetCategory.all) return true;
    return filterFor(category) == this;
  }
}

/// Currently selected closet category chip.
class ClosetCategoryNotifier extends Notifier<ClosetCategory> {
  @override
  ClosetCategory build() => ClosetCategory.all;

  void select(ClosetCategory category) => state = category;
}

final closetCategoryProvider =
    NotifierProvider<ClosetCategoryNotifier, ClosetCategory>(
      ClosetCategoryNotifier.new,
    );
