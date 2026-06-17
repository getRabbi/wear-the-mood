import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/wardrobe_item.dart';

/// A garment colour the closet can be filtered by. Swatch colours are *content*
/// (they represent real clothing colours), not UI chrome — so literal values are
/// intentional here, unlike the design tokens used for app surfaces.
class ClosetColor {
  const ClosetColor(this.key, this.label, this.swatch, this._keywords);

  final String key;
  final String label;
  final Color swatch;
  final List<String> _keywords;

  bool matchesText(String text) => _keywords.any(text.contains);
}

/// The recognised palette, checked in order (most specific first where it
/// matters). Keys are stable; labels are user-facing.
const _palette = <ClosetColor>[
  ClosetColor('black', 'Black', Color(0xFF1A1A1A), [
    'black', 'charcoal', 'jet', 'onyx',
  ]),
  ClosetColor('white', 'White', Color(0xFFF5F5F5), [
    'white', 'ivory', 'cream', 'off-white', 'off white',
  ]),
  ClosetColor('grey', 'Grey', Color(0xFF9AA0A6), [
    'grey', 'gray', 'silver', 'slate',
  ]),
  ClosetColor('beige', 'Beige', Color(0xFFD8C3A5), [
    'beige', 'tan', 'khaki', 'camel', 'nude', 'sand', 'taupe',
  ]),
  ClosetColor('brown', 'Brown', Color(0xFF7B4B2A), [
    'brown', 'chocolate', 'coffee', 'mocha', 'walnut',
  ]),
  ClosetColor('red', 'Red', Color(0xFFD7263D), [
    'red', 'crimson', 'maroon', 'burgundy', 'wine', 'scarlet',
  ]),
  ClosetColor('pink', 'Pink', Color(0xFFF48FB1), [
    'pink', 'rose', 'blush', 'fuchsia', 'magenta',
  ]),
  ClosetColor('orange', 'Orange', Color(0xFFF57C00), [
    'orange', 'rust', 'terracotta', 'peach', 'coral', 'apricot',
  ]),
  ClosetColor('yellow', 'Yellow', Color(0xFFFBC02D), [
    'yellow', 'mustard', 'gold', 'amber', 'lemon',
  ]),
  ClosetColor('green', 'Green', Color(0xFF3F9D52), [
    'green', 'olive', 'emerald', 'mint', 'sage', 'teal', 'forest',
  ]),
  ClosetColor('blue', 'Blue', Color(0xFF2F6FED), [
    'blue', 'navy', 'denim', 'indigo', 'cobalt', 'sky', 'azure',
  ]),
  ClosetColor('purple', 'Purple', Color(0xFF8B35FF), [
    'purple', 'violet', 'lavender', 'lilac', 'plum', 'mauve',
  ]),
];

/// The recognised colour palette (for pickers like Categorize). Read-only view
/// of the internal palette so callers can offer swatch chips.
List<ClosetColor> get closetColorPalette => _palette;

/// Resolve a wardrobe item to a palette colour, or null if undetectable.
///
/// Prefers the item's tagged `color` (from the vision worker); falls back —
/// clearly secondarily — to scanning tags / title / category so the UI still
/// works before AI tagging has run. Returns null rather than guessing wildly.
ClosetColor? resolveItemColor(WardrobeItem item) {
  // Primary signal: the explicit colour field.
  final primary = (item.color ?? '').toLowerCase();
  if (primary.isNotEmpty) {
    for (final c in _palette) {
      if (c.matchesText(primary)) return c;
    }
  }
  // Secondary fallback: tags + title + category.
  final secondary = [
    ...item.tags,
    item.title ?? '',
    item.category ?? '',
  ].join(' ').toLowerCase();
  if (secondary.isEmpty) return null;
  for (final c in _palette) {
    if (c.matchesText(secondary)) return c;
  }
  return null;
}

/// Distinct colours actually present in [items], with counts, palette-ordered.
List<({ClosetColor color, int count})> closetColorCounts(
  List<WardrobeItem> items,
) {
  final counts = <String, int>{};
  for (final item in items) {
    final c = resolveItemColor(item);
    if (c != null) counts[c.key] = (counts[c.key] ?? 0) + 1;
  }
  return [
    for (final c in _palette)
      if (counts.containsKey(c.key)) (color: c, count: counts[c.key]!),
  ];
}

/// The selected closet colour filter (palette key, or null for "all colours").
/// Client-side only — filters the already-loaded closet, no new endpoint.
class ClosetColorFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? key) =>
      state = (state == key) ? null : key; // tap again to clear

  /// Force-set a colour (used when jumping in from the Color Map).
  void set(String key) => state = key;

  void clear() => state = null;
}

final closetColorFilterProvider =
    NotifierProvider<ClosetColorFilter, String?>(ClosetColorFilter.new);

/// Whether [item] matches the active colour filter (true when no filter set).
bool itemMatchesColorFilter(WardrobeItem item, String? filterKey) {
  if (filterKey == null) return true;
  return resolveItemColor(item)?.key == filterKey;
}

/// A horizontal row of colour-filter swatch chips for the colours actually
/// present in [items]. Silent (renders nothing) when no colours are detectable,
/// so the UI never shows fake swatches. Tapping a swatch toggles the filter.
class ClosetColorChips extends ConsumerWidget {
  const ClosetColorChips({super.key, required this.items});

  final List<WardrobeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final present = closetColorCounts(items);
    if (present.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(closetColorFilterProvider);

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: present.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final entry = present[i];
          final isSel = entry.color.key == selected;
          return Center(
            child: GestureDetector(
              onTap: () => ref
                  .read(closetColorFilterProvider.notifier)
                  .select(entry.color.key),
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                decoration: BoxDecoration(
                  color: isSel
                      ? const Color(0x29C084FC) // accentSoft lavender
                      : const Color(0x14FFFFFF), // glassFill
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSel
                        ? const Color(0xFFC084FC)
                        : const Color(0x1AFFFFFF),
                    width: isSel ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: entry.color.swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.color.label} ${entry.count}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
