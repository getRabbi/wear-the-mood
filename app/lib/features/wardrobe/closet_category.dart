import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import 'garment_category.dart';

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

/// The closet's filter chips.
///
/// These ARE the twelve [kGarmentCategories], plus `all` and `favorites`. Not a
/// grouping of them, not a mapping onto them — the same list, in the same order,
/// with the same labels.
///
/// It has been wrong twice, in opposite ways, and both were visible in the app:
///
///   * originally these seven matched a piece's free-text category by KEYWORD
///     ("does it contain 'top'"), so `Hijab` and `Eyewear` matched nothing and
///     vanished from every chip, while `laptop bag` would have matched Tops;
///   * then they became an explicit seven-way grouping of the twelve, which was
///     at least honest but still showed a person a different vocabulary in the
///     closet from the one they had just chosen from after background removal.
///     Somebody who deliberately saved a piece as "Hijab" then had to know it
///     lives under "Accessories" to find it again.
///
/// Deriving the label and the match from [kGarmentCategories] is what stops a
/// third version of this: there is no second list to keep in step.
enum ClosetCategory {
  all,
  tops,
  bottoms,
  dresses,
  outerwear,
  shoes,
  bags,
  hijab,
  hats,
  eyewear,
  jewelry,
  belts,
  other,
  favorites,
}

extension ClosetCategoryX on ClosetCategory {
  /// The picker entry this chip is, or null for `all` / `favorites`.
  ///
  /// Resolved from the enum's own `name`, which is the stored value lowercased
  /// (`tops` -> "Tops", `hijab` -> "Hijab"). `closet_category_test` asserts the
  /// two stay aligned, so a rename on either side fails a test rather than
  /// quietly emptying a chip.
  GarmentCategory? get garment => switch (this) {
    ClosetCategory.all || ClosetCategory.favorites => null,
    _ => garmentCategoryOf(name),
  };

  String label(AppLocalizations l10n) => switch (this) {
    ClosetCategory.all => l10n.closetCatAll,
    ClosetCategory.favorites => l10n.closetCatFavorites,
    // The SAME label the picker showed when the piece was saved.
    _ => garment?.label(l10n) ?? name,
  };

  /// The chip a stored category belongs under, or null when the value is not
  /// one of the twelve.
  ///
  /// Null is the honest answer for a legacy free-text value ("Party",
  /// "accessories", something typed before the picker existed). Such a piece
  /// stays fully visible under "All" and the review banner offers to repair it;
  /// it is never guessed into a chip its owner did not choose.
  static ClosetCategory? filterFor(String? category) {
    final value = garmentCategoryOf(category)?.value.toLowerCase();
    if (value == null) return null;
    for (final c in ClosetCategory.values) {
      if (c.garment?.value.toLowerCase() == value) return c;
    }
    return null;
  }

  /// Whether a piece belongs under this filter chip.
  bool matches(String? category) {
    if (this == ClosetCategory.all) return true;
    final mine = garment;
    if (mine == null) return false; // favorites is handled by the caller
    return garmentCategoryOf(category)?.value == mine.value;
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
