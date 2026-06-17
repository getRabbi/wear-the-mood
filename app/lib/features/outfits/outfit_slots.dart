import 'package:flutter/material.dart';

import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';

/// The slots that make up a full outfit set (real-device polish — Build Outfit
/// is now a proper set builder: top + bottom + shoes + bag + eyewear …). Order
/// defines the layout and the saved item order. Each slot holds one piece; items
/// that don't fit a slot are preserved as "extras" so an edit round-trip never
/// drops pieces.
enum OutfitSlot {
  top,
  bottom,
  dress,
  outerwear,
  shoes,
  bag,
  hijabScarf,
  eyewear,
  jewelry,
}

extension OutfitSlotX on OutfitSlot {
  String label(AppLocalizations l10n) => switch (this) {
    OutfitSlot.top => l10n.slotTop,
    OutfitSlot.bottom => l10n.slotBottom,
    OutfitSlot.dress => l10n.slotDress,
    OutfitSlot.outerwear => l10n.slotOuterwear,
    OutfitSlot.shoes => l10n.slotShoes,
    OutfitSlot.bag => l10n.slotBag,
    OutfitSlot.hijabScarf => l10n.slotHijabScarf,
    OutfitSlot.eyewear => l10n.slotEyewear,
    OutfitSlot.jewelry => l10n.slotJewelry,
  };

  IconData get icon => switch (this) {
    OutfitSlot.top => Icons.checkroom,
    OutfitSlot.bottom => Icons.dry_cleaning,
    OutfitSlot.dress => Icons.woman,
    OutfitSlot.outerwear => Icons.ac_unit,
    OutfitSlot.shoes => Icons.directions_run,
    OutfitSlot.bag => Icons.shopping_bag_outlined,
    OutfitSlot.hijabScarf => Icons.face_3_outlined,
    OutfitSlot.eyewear => Icons.remove_red_eye_outlined,
    OutfitSlot.jewelry => Icons.diamond_outlined,
  };

  /// Category/title keywords that map a piece into this slot.
  List<String> get keywords => switch (this) {
    OutfitSlot.top => const [
      'top', 'shirt', 'tee', 't-shirt', 'blouse', 'sweater', 'knit', 'hoodie',
      'jumper', 'cardigan', 'tunic', 'kurti',
    ],
    OutfitSlot.bottom => const [
      'bottom', 'pant', 'trouser', 'jean', 'short', 'skirt', 'legging', 'chino',
    ],
    OutfitSlot.dress => const ['dress', 'gown', 'jumpsuit', 'romper', 'traditional'],
    OutfitSlot.outerwear => const [
      'jacket', 'coat', 'blazer', 'outer', 'trench', 'parka', 'puffer', 'vest', 'winter',
    ],
    OutfitSlot.shoes => const [
      'shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer', 'trainer',
    ],
    OutfitSlot.bag => const ['bag', 'purse', 'tote', 'clutch', 'backpack', 'satchel'],
    OutfitSlot.hijabScarf => const ['hijab', 'scarf', 'shawl', 'modest'],
    OutfitSlot.eyewear => const ['glass', 'sunglass', 'eyewear', 'specs', 'goggle'],
    OutfitSlot.jewelry => const [
      'jewel', 'watch', 'belt', 'hat', 'cap', 'tie', 'accessor', 'ring',
      'necklace', 'earring', 'bracelet',
    ],
  };

  /// Whether a piece's category/title text belongs to this slot.
  bool matches(WardrobeItem item) {
    final text = '${item.category ?? ''} ${item.title ?? ''} ${item.tags.join(' ')}'
        .toLowerCase();
    if (text.trim().isEmpty) return false;
    return keywords.any(text.contains);
  }
}

/// The best slot for an item, or null when nothing matches (→ "extras").
OutfitSlot? slotForItem(WardrobeItem item) {
  for (final slot in OutfitSlot.values) {
    if (slot.matches(item)) return slot;
  }
  return null;
}
