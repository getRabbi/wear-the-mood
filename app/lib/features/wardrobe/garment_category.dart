import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../tryon/garment_role.dart';

/// THE ONE list of categories a person may choose for a garment.
///
/// Every picker in the app — Add Garment, Edit piece, the legacy-item resolver —
/// reads this list and nothing else. Before it existed there were three separate
/// ideas of what a category was:
///
///   * `ClosetCategory` (a FILTER enum) drove the shipping Add Garment screen,
///     so a hijab, a watch and a pair of sunglasses all had to be saved as
///     "Accessories" — a word the server deliberately refuses to read as a body
///     region, which made every one of those pieces permanently unrenderable;
///   * `kCategoryGroups` (30 values) drove the legacy screens and offered six
///     lifestyle buckets ("Party", "Travel") that name WHEN a piece is worn
///     rather than WHAT it is, and resolve to nothing for the same reason;
///   * `garment_role.dart` held the real canonical mapping, and agreed with
///     neither picker.
///
/// [value] is the string stored in `wardrobe_items.category`. Each one is a
/// value the taxonomy on the server ALREADY maps exactly (`_EXACT` in
/// `backend/app/services/tryon/taxonomy.py`), so nothing here renames a stored
/// value or needs a data migration — it only stops the pickers from offering
/// words the renderer cannot act on.
///
/// [role] is the canonical try-on role that value resolves to. It is duplicated
/// here so the UI can say what a choice MEANS before the round trip; the server
/// re-derives it on every write and is the authority. `garment_category_test`
/// asserts the two agree, and `test_taxonomy_picker_parity` asserts the Python
/// side maps every [value] to the same [role].
///
/// There is no automatic classification anywhere in this file. No AI, no title
/// guessing, no "first category wins" default — a garment's category is whatever
/// the person who owns it said it is.
@immutable
class GarmentCategory {
  const GarmentCategory({
    required this.value,
    required this.role,
    required this.icon,
    required this.labelOf,
    required this.examplesOf,
  });

  /// Stored verbatim in `wardrobe_items.category`.
  final String value;

  /// The canonical role this value resolves to (`garment_role.dart`).
  final String role;

  /// A silhouette for the tile. Decorative reinforcement — the label and the
  /// examples carry the meaning, so an imperfect glyph never misleads.
  final IconData icon;

  final String Function(AppLocalizations) labelOf;

  /// Two to four concrete garments, so "Bottoms" is never a guess. This is the
  /// line that stops a tank top being filed under trousers.
  final String Function(AppLocalizations) examplesOf;

  String label(AppLocalizations l10n) => labelOf(l10n);

  String examples(AppLocalizations l10n) => examplesOf(l10n);

  /// Whether the ACTIVE try-on provider can render this role onto a body.
  ///
  /// False is a statement about the provider, never about the piece: a belt is
  /// a perfectly good closet item that today's model cannot wear. Saying so on
  /// the tile is the honest alternative to letting somebody pick it, save it,
  /// and discover the limit only when a look silently comes back without it.
  bool get isTryOnCapable => kTryOnCapableRoles.contains(role);
}

/// The twelve choices, in the order they are shown.
///
/// Apparel first (what most pieces are), then footwear and carried, then the
/// head/face group, then the two honest non-renderables last. The order is
/// deliberate and NOT alphabetical: the first tile is the most likely answer,
/// but nothing is ever preselected — see [WtmCategoryPicker].
///
/// Every try-on-capable canonical role appears exactly once, which is the
/// property that matters: a person can now express "this is a hijab" or "this is
/// a watch" instead of being funnelled into a bucket that means nothing.
final List<GarmentCategory> kGarmentCategories = <GarmentCategory>[
  GarmentCategory(
    value: 'Tops',
    role: kRoleTop,
    icon: Icons.checkroom_rounded,
    labelOf: (l) => l.catTops,
    examplesOf: (l) => l.catExTops,
  ),
  GarmentCategory(
    value: 'Bottoms',
    role: kRoleBottom,
    icon: Icons.dry_cleaning_rounded,
    labelOf: (l) => l.catBottoms,
    examplesOf: (l) => l.catExBottoms,
  ),
  GarmentCategory(
    value: 'Dresses',
    role: kRoleOnePiece,
    icon: Icons.woman_rounded,
    labelOf: (l) => l.catDresses,
    examplesOf: (l) => l.catExDresses,
  ),
  GarmentCategory(
    value: 'Outerwear',
    role: kRoleOuterwear,
    icon: Icons.ac_unit_rounded,
    labelOf: (l) => l.catOuterwear,
    examplesOf: (l) => l.catExOuterwear,
  ),
  GarmentCategory(
    value: 'Shoes',
    role: kRoleShoes,
    icon: Icons.hiking_rounded,
    labelOf: (l) => l.catShoes,
    examplesOf: (l) => l.catExShoes,
  ),
  GarmentCategory(
    value: 'Bags',
    role: kRoleBag,
    icon: Icons.shopping_bag_rounded,
    labelOf: (l) => l.catBags,
    examplesOf: (l) => l.catExBags,
  ),
  GarmentCategory(
    value: 'Hijab',
    role: kRoleHijabScarf,
    icon: Icons.face_retouching_natural_rounded,
    labelOf: (l) => l.catHijab,
    examplesOf: (l) => l.catExHijab,
  ),
  GarmentCategory(
    value: 'Hats',
    role: kRoleHatHeadwear,
    icon: Icons.school_rounded,
    labelOf: (l) => l.catHats,
    examplesOf: (l) => l.catExHats,
  ),
  GarmentCategory(
    value: 'Eyewear',
    role: kRoleGlasses,
    icon: Icons.remove_red_eye_rounded,
    labelOf: (l) => l.catEyewear,
    examplesOf: (l) => l.catExEyewear,
  ),
  GarmentCategory(
    value: 'Jewelry',
    role: kRoleJewelry,
    icon: Icons.diamond_rounded,
    labelOf: (l) => l.catJewelry,
    examplesOf: (l) => l.catExJewelry,
  ),
  GarmentCategory(
    value: 'Belts',
    role: kRoleBelt,
    icon: Icons.linear_scale_rounded,
    labelOf: (l) => l.catBelts,
    examplesOf: (l) => l.catExBelts,
  ),
  GarmentCategory(
    value: 'Other',
    role: kRoleOther,
    icon: Icons.category_rounded,
    labelOf: (l) => l.catOther,
    examplesOf: (l) => l.catExOther,
  ),
];

/// The entry for a stored value, or null when the value is not one we offer.
///
/// EXACT (case-insensitive) match only. Deliberately not a keyword or phrase
/// match: the Edit sheet uses this to decide what to show as already-selected,
/// and a fuzzy match there would silently re-affirm a category nobody chose —
/// which is how a wrong one survives being "reviewed". A legacy value we do not
/// recognise answers null, and the picker then shows nothing selected and asks.
GarmentCategory? garmentCategoryOf(String? value) {
  final key = (value ?? '').trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final c in kGarmentCategories) {
    if (c.value.toLowerCase() == key) return c;
  }
  return null;
}

/// Whether [value] is one of the twelve, i.e. something the server will resolve
/// to a real body region. Used to gate Save.
bool isChoosableGarmentCategory(String? value) =>
    garmentCategoryOf(value) != null;
