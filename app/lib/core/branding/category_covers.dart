/// Curated DEFAULT cover imagery for the wardrobe drawers, outfit-builder slots,
/// the "Today" guide cards, and the packing planner (CATEGORY_COVER_IMAGES.md).
///
/// The single source of truth mapping a category/slot KEY → a cover asset. The
/// images are decorative category illustrations / empty-slot placeholders that
/// you own (AI-generated or licensed) — NEVER a claim that the user owns that
/// exact item. The moment a user adds their own piece, their real image wins;
/// these only fill empty/new surfaces.
///
/// Until the owned WebP set is added under `assets/covers/` AND registered in
/// pubspec, [kCoverImagesEnabled] stays `false` so every surface uses its
/// built-in icon/gradient fallback — the app builds and ships with zero image
/// assets and no missing-asset errors. Flip the flag (and register the assets)
/// to light them all up at once.
library;

/// Master switch. `false` ⇒ all surfaces fall back to their existing look.
/// Set to `true` only once the assets exist under `assets/covers/` and are
/// declared in `pubspec.yaml` (otherwise covers fall back per-image anyway).
const bool kCoverImagesEnabled = false;

/// category/slot key → cover asset path (one place, per the spec). Keys are
/// stable strings each surface computes from its own taxonomy.
const Map<String, String> kCategoryCovers = {
  // Wardrobe category / drawer covers.
  'tops': 'assets/covers/cover_tops.webp',
  'bottoms': 'assets/covers/cover_bottoms.webp',
  'dresses': 'assets/covers/cover_dresses.webp',
  'outerwear': 'assets/covers/cover_outerwear.webp',
  'blazers': 'assets/covers/cover_blazers.webp',
  'knitwear': 'assets/covers/cover_knitwear.webp',
  'shoes': 'assets/covers/cover_shoes.webp',
  'bags': 'assets/covers/cover_bags.webp',
  'accessories': 'assets/covers/cover_accessories.webp',

  // Outfit-builder slot covers (empty-slot placeholders).
  'slot_top': 'assets/covers/slot_top.webp',
  'slot_bottom': 'assets/covers/slot_bottom.webp',
  'slot_dress': 'assets/covers/slot_dress.webp',
  'slot_outerwear': 'assets/covers/slot_outerwear.webp',
  'slot_shoes': 'assets/covers/slot_shoes.webp',
  'slot_bag': 'assets/covers/slot_bag.webp',
  'slot_accessories': 'assets/covers/slot_accessories.webp',

  // Editorial scene covers for Today / guide + packing.
  'today_layering': 'assets/covers/today_layering.webp',
  'pack_capsule': 'assets/covers/pack_capsule.webp',
};

/// The cover asset for [key], or `null` when covers are disabled or the key is
/// unmapped — callers then render their own fallback. This is the ONLY gate a
/// surface needs: `coverAsset(key) == null ? fallback : image`.
String? coverAsset(String key) =>
    kCoverImagesEnabled ? kCategoryCovers[key] : null;
