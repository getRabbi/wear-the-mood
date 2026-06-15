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

/// Closet filter categories (redesign spec). `all` and `favorites` are handled
/// specially; the rest match against an item's free-text `category` via keyword
/// sets, so they work regardless of exactly how the backend tagged the piece.
enum ClosetCategory { all, tops, bottoms, dresses, outerwear, shoes, bags, accessories, favorites }

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

  /// Keyword set used to match a piece's free-text category. Empty for the
  /// special `all`/`favorites` cases (handled by the caller).
  List<String> get _keywords => switch (this) {
    ClosetCategory.tops => const [
      'top', 'shirt', 'tee', 't-shirt', 'blouse', 'sweater', 'knit', 'hoodie', 'jumper', 'cardigan',
    ],
    ClosetCategory.bottoms => const [
      'bottom', 'pant', 'trouser', 'jean', 'short', 'skirt', 'legging', 'chino',
    ],
    ClosetCategory.dresses => const ['dress', 'gown', 'jumpsuit', 'romper'],
    ClosetCategory.outerwear => const [
      'jacket', 'coat', 'blazer', 'outer', 'trench', 'parka', 'puffer', 'vest',
    ],
    ClosetCategory.shoes => const [
      'shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer', 'trainer',
    ],
    ClosetCategory.bags => const ['bag', 'purse', 'tote', 'clutch', 'backpack', 'satchel'],
    ClosetCategory.accessories => const [
      'accessor', 'hat', 'cap', 'scarf', 'belt', 'glass', 'sunglass', 'jewel', 'watch', 'tie', 'sock',
    ],
    ClosetCategory.all || ClosetCategory.favorites => const [],
  };

  /// Whether a piece's category text belongs to this filter.
  bool matches(String? category) {
    if (this == ClosetCategory.all) return true;
    final c = (category ?? '').toLowerCase();
    if (c.isEmpty) return false;
    return _keywords.any(c.contains);
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
