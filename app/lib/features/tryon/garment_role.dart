/// Client-side MIRROR of the canonical garment taxonomy (spec Phases 2, 27).
///
/// The server is the authority. `backend/app/services/tryon/taxonomy.py` decides
/// what a piece is, whether it can be rendered, and what the look's plan looks
/// like; this file exists so the UI can answer the same questions a frame
/// earlier — greying out a Try On that would be refused, warning about a
/// conflict before a round trip — without ever being able to grant something the
/// server would deny.
///
/// It is deliberately SMALLER than the server's version. The server has to read
/// merchant free text and marketing titles, so it carries a phrase table; the
/// app only has to read its own closet picker, which is a closed list defined in
/// `wardrobe_categories.dart`. Anything this file does not recognise falls
/// through to `null`, and `null` means "ask the server" — never "assume it's a
/// top".
library;

/// Canonical roles, matching `CANONICAL_CATEGORIES` on the server.
const String kRoleTop = 'top';
const String kRoleBottom = 'bottom';
const String kRoleOnePiece = 'one_piece';
const String kRoleOuterwear = 'outerwear';
const String kRoleHijabScarf = 'hijab_scarf';
const String kRoleGlasses = 'glasses';
const String kRoleHatHeadwear = 'hat_headwear';
const String kRoleShoes = 'shoes';
const String kRoleBag = 'bag';
const String kRoleJewelry = 'jewelry';
const String kRoleBelt = 'belt';
const String kRoleOther = 'other';

/// A photo of a COMPLETE outfit used as a reference — what "Try this look" on a
/// community post hands the studio. Not a closet category: no picker offers it,
/// and only that handoff sets it.
const String kLookReferenceCategory = 'look_reference';

/// Roles the current provider can actually render. Mirrors
/// `TRYON_CAPABLE_CATEGORIES`; the server re-checks, so this only ever hides an
/// affordance early.
const Set<String> kTryOnCapableRoles = {
  kRoleTop,
  kRoleBottom,
  kRoleOnePiece,
  kRoleOuterwear,
  kRoleHijabScarf,
  kRoleGlasses,
  kRoleHatHeadwear,
  kRoleShoes,
  kRoleBag,
  kRoleJewelry,
  kLookReferenceCategory,
};

/// Roles that cover the whole body, so they cannot share a look with a separate
/// top or bottom (or with each other).
const Set<String> kWholeBodyRoles = {kRoleOnePiece, kLookReferenceCategory};

/// The app's own closet taxonomy (`wardrobe_categories.dart` values) mapped to
/// canonical roles. A closed set, so an exact lookup is enough — the server's
/// phrase matching exists for merchant feeds, which never reach this file.
const Map<String, String> _closetRoles = {
  'tops': kRoleTop,
  't-shirts': kRoleTop,
  'shirts': kRoleTop,
  'blouses': kRoleTop,
  'tunics/kurtis': kRoleTop,
  'bottoms': kRoleBottom,
  'pants': kRoleBottom,
  'jeans': kRoleBottom,
  'skirts': kRoleBottom,
  'shorts': kRoleBottom,
  'dresses': kRoleOnePiece,
  'traditional': kRoleOnePiece,
  'outerwear': kRoleOuterwear,
  'winter': kRoleOuterwear,
  'shoes': kRoleShoes,
  'hijab': kRoleHijabScarf,
  'scarves': kRoleHijabScarf,
  'bags': kRoleBag,
  'eyewear': kRoleGlasses,
  'jewelry': kRoleJewelry,
  'belts': kRoleBelt,
  'hats': kRoleHatHeadwear,
  'other': kRoleOther,
  // Activewear / Sleepwear / Swimwear / Workwear / Party / Travel / Accessories
  // are ABSENT on purpose. They say WHEN a piece is worn, not WHAT it is, so
  // they resolve to null and let the server answer from the item's name —
  // "Activewear" + "Running Shorts" is a bottom, and "Activewear" on its own
  // genuinely is unknown. Listing them here with a guessed role is precisely
  // the shortcut this whole change removes.
};

/// The canonical role for a stored category value, or null when this file
/// cannot say. Null is not a failure — it means the server decides.
String? canonicalRoleOf(String? category) {
  final key = (category ?? '').trim().toLowerCase();
  if (key.isEmpty) return null;
  if (kTryOnCapableRoles.contains(key) || key == kRoleBelt || key == kRoleOther) {
    return key; // already canonical
  }
  return _closetRoles[key];
}

/// Whether a piece looks renderable to the UI. False only when this file is
/// SURE (a known-but-unsupported role); an unknown category answers true and
/// lets the server give the real answer with a real message.
bool looksTryOnCapable(String? category) {
  final role = canonicalRoleOf(category);
  if (role == null) return true;
  return kTryOnCapableRoles.contains(role);
}

/// Whether a closet piece has nothing at all to identify it, so a render would
/// have to guess what it is.
///
/// Both fields, not either: the server resolves a role from the category first
/// and the name second, so "Running Shorts" with no category is perfectly
/// renderable and must not be blocked here. This is only the genuinely empty
/// case — the piece somebody added before name and category were required.
bool needsCategoryForTryOn({String? category, String? title}) =>
    (category ?? '').trim().isEmpty && (title ?? '').trim().isEmpty;

/// The conflict in a selection, as a role pair, or null when there is none.
///
/// Mirrors the server's rules so the picker can warn in place instead of letting
/// someone reach Generate and be refused: two pieces for the same body region,
/// or a whole-body piece alongside a separate top or bottom.
({String a, String b})? conflictIn(List<String?> categories) {
  final seen = <String>{};
  for (final category in categories) {
    final role = canonicalRoleOf(category);
    if (role == null || !kTryOnCapableRoles.contains(role)) continue;
    if (!seen.add(role)) return (a: role, b: role);
  }
  for (final whole in kWholeBodyRoles) {
    if (!seen.contains(whole)) continue;
    for (final part in const [kRoleTop, kRoleBottom, kRoleOuterwear]) {
      if (seen.contains(part)) return (a: whole, b: part);
    }
    for (final other in kWholeBodyRoles) {
      if (other != whole && seen.contains(other)) return (a: whole, b: other);
    }
  }
  return null;
}
