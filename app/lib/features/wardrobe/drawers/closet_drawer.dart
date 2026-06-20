import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// A fixed, tree-shake-safe set of drawer icons (const [IconData] only — never
/// dynamic codepoints, which would break `flutter build` icon tree-shaking).
enum DrawerIconKind {
  hanger(Icons.checkroom),
  shirt(Icons.dry_cleaning),
  drawer(Icons.inventory_2_outlined),
  dress(Icons.checkroom_rounded),
  shoes(Icons.directions_run),
  bag(Icons.shopping_bag_outlined),
  accessory(Icons.diamond_outlined),
  watch(Icons.watch_outlined),
  winter(Icons.ac_unit),
  summer(Icons.wb_sunny_outlined),
  work(Icons.work_outline),
  party(Icons.celebration_outlined),
  travel(Icons.luggage_outlined),
  sparkle(Icons.auto_awesome),
  favorite(Icons.favorite),
  box(Icons.archive_outlined);

  const DrawerIconKind(this.data);
  final IconData data;
}

/// Whether a drawer hangs on the rail (dresses, coats, tops) or is a folded
/// drawer / shelf (tees, pants, accessories). Drives the wardrobe layout.
enum ClosetDrawerKind { rail, drawer }

/// A preset accent palette for drawers (vivid on the Midnight Plum theme).
const drawerAccentPalette = <int>[
  0xFFF43F7F, // rose
  0xFF8B35FF, // violet
  0xFFC084FC, // lavender
  0xFF4ADE80, // green
  0xFF38BDF8, // sky
  0xFFFBBF24, // amber
  0xFFFB7185, // coral
  0xFF2DD4BF, // teal
];

/// A user wardrobe "drawer" / section (CLAUDE.md §5). Stored locally (no backend
/// migration), so existing closet items keep working and unassigned items fall
/// into "Unsorted". JSON-serialized into encrypted device storage.
class ClosetDrawer {
  ClosetDrawer({
    required this.id,
    required this.name,
    required this.iconKind,
    required this.accentValue,
    required this.kind,
    required this.sortOrder,
    this.keywords = const [],
    this.isDefault = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String name;
  final DrawerIconKind iconKind;

  /// ARGB color value of the drawer's accent.
  final int accentValue;
  final ClosetDrawerKind kind;
  final int sortOrder;

  /// Category keywords used to auto-collect unassigned items by their category.
  final List<String> keywords;

  /// Seeded default drawer (kept distinct from user-created ones).
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;

  IconData get icon => iconKind.data;
  Color get accent => Color(accentValue);

  ClosetDrawer copyWith({
    String? name,
    DrawerIconKind? iconKind,
    int? accentValue,
    ClosetDrawerKind? kind,
    int? sortOrder,
  }) => ClosetDrawer(
    id: id,
    name: name ?? this.name,
    iconKind: iconKind ?? this.iconKind,
    accentValue: accentValue ?? this.accentValue,
    kind: kind ?? this.kind,
    sortOrder: sortOrder ?? this.sortOrder,
    keywords: keywords,
    isDefault: isDefault,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': iconKind.name,
    'accent': accentValue,
    'kind': kind.name,
    'sort': sortOrder,
    'keywords': keywords,
    'is_default': isDefault,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ClosetDrawer.fromJson(Map<String, dynamic> json) => ClosetDrawer(
    id: json['id'] as String,
    name: json['name'] as String,
    iconKind: DrawerIconKind.values.asNameMap()[json['icon']] ??
        DrawerIconKind.drawer,
    accentValue: json['accent'] as int? ?? AppColors.violet.toARGB32(),
    kind: ClosetDrawerKind.values.asNameMap()[json['kind']] ??
        ClosetDrawerKind.drawer,
    sortOrder: json['sort'] as int? ?? 0,
    keywords: (json['keywords'] as List?)?.cast<String>() ?? const [],
    isDefault: json['is_default'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
  );
}

/// The curated cover-image key for a drawer (CATEGORY_COVER_IMAGES.md) — derived
/// from the drawer's own name + keywords so renamed/custom drawers still resolve
/// to the closest category illustration. Falls back to `tops`. Only used as a
/// DECORATIVE cover for an empty/new drawer; real item thumbnails always win.
String drawerCoverKey(ClosetDrawer drawer) {
  final hay = '${drawer.name} ${drawer.keywords.join(' ')}'.toLowerCase();
  bool has(List<String> needles) => needles.any(hay.contains);
  if (has(['dress', 'gown', 'jumpsuit', 'traditional', 'abaya'])) {
    return 'dresses';
  }
  if (has(['blazer', 'suit'])) return 'blazers';
  if (has(['coat', 'jacket', 'outer', 'trench', 'parka', 'puffer'])) {
    return 'outerwear';
  }
  if (has(['knit', 'sweater', 'wool', 'fleece', 'thermal', 'winter'])) {
    return 'knitwear';
  }
  if (has(['shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer'])) {
    return 'shoes';
  }
  if (has(['bag', 'purse', 'tote', 'clutch', 'backpack', 'satchel'])) {
    return 'bags';
  }
  if (has([
    'accessor', 'watch', 'jewel', 'belt', 'hat', 'cap', 'glass', 'tie',
    'hijab', 'scarf', 'modest',
  ])) {
    return 'accessories';
  }
  if (has(['pant', 'trouser', 'jean', 'skirt', 'short', 'legging', 'bottom'])) {
    return 'bottoms';
  }
  return 'tops';
}

/// The seeded default wardrobe (created on first run; users can rename/delete).
List<ClosetDrawer> defaultDrawers() {
  final p = drawerAccentPalette;
  final now = DateTime.now();
  ClosetDrawer d(
    int i,
    String id,
    String name,
    DrawerIconKind icon,
    ClosetDrawerKind kind,
    List<String> keywords,
  ) => ClosetDrawer(
    id: 'def_$id',
    name: name,
    iconKind: icon,
    accentValue: p[i % p.length],
    kind: kind,
    sortOrder: i,
    keywords: keywords,
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );

  return [
    d(0, 'tops', 'Tops', DrawerIconKind.hanger, ClosetDrawerKind.rail,
        ['top', 'shirt', 'blouse', 'sweater', 'knit', 'hoodie', 'cardigan']),
    d(1, 'tshirts', 'T-Shirts', DrawerIconKind.shirt, ClosetDrawerKind.drawer,
        ['t-shirt', 'tee', 'tshirt']),
    d(2, 'pants', 'Pants', DrawerIconKind.drawer, ClosetDrawerKind.drawer,
        ['pant', 'trouser', 'jean', 'chino', 'short', 'legging', 'bottom']),
    d(3, 'dresses', 'Dresses', DrawerIconKind.dress, ClosetDrawerKind.rail,
        ['dress', 'gown', 'jumpsuit', 'skirt']),
    d(4, 'hijab', 'Hijab', DrawerIconKind.accessory, ClosetDrawerKind.drawer,
        ['hijab', 'scarf', 'modest', 'abaya']),
    d(5, 'shoes', 'Shoes', DrawerIconKind.shoes, ClosetDrawerKind.drawer,
        ['shoe', 'sneaker', 'boot', 'heel', 'sandal', 'loafer']),
    d(6, 'bags', 'Bags', DrawerIconKind.bag, ClosetDrawerKind.drawer,
        ['bag', 'purse', 'tote', 'clutch', 'backpack']),
    d(7, 'accessories', 'Accessories', DrawerIconKind.watch,
        ClosetDrawerKind.drawer,
        ['accessor', 'belt', 'glass', 'watch', 'jewel', 'hat', 'cap', 'tie']),
    d(8, 'outerwear', 'Outerwear', DrawerIconKind.hanger, ClosetDrawerKind.rail,
        ['jacket', 'coat', 'blazer', 'trench', 'parka', 'puffer']),
    d(9, 'winter', 'Winter', DrawerIconKind.winter, ClosetDrawerKind.drawer,
        ['wool', 'thermal', 'fleece']),
    d(10, 'workwear', 'Workwear', DrawerIconKind.work, ClosetDrawerKind.drawer,
        ['work', 'office', 'formal', 'suit']),
    d(11, 'party', 'Party', DrawerIconKind.party, ClosetDrawerKind.drawer,
        ['party', 'sequin', 'evening']),
    d(12, 'travel', 'Travel', DrawerIconKind.travel, ClosetDrawerKind.drawer,
        ['travel', 'trip', 'vacation']),
  ];
}
