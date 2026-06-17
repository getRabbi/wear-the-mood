import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

/// One wardrobe category in the taxonomy (real-device polish — the old five
/// chips were too limited). [value] is the canonical English string stored on
/// the item, so existing items keep matching their drawers/filters; [labelOf]
/// localizes it for display.
class WardrobeCategory {
  const WardrobeCategory(this.value, this.labelOf);

  final String value;
  final String Function(AppLocalizations) labelOf;

  String label(AppLocalizations l10n) => labelOf(l10n);
}

/// A titled group of categories, for the compact grouped picker sheet.
class WardrobeCategoryGroup {
  const WardrobeCategoryGroup(this.titleOf, this.categories);

  final String Function(AppLocalizations) titleOf;
  final List<WardrobeCategory> categories;
}

/// The full clothing taxonomy, grouped so the picker stays tidy instead of a
/// wall of 30 chips (spec). Order matters: the first entry of each group also
/// seeds [primaryCategories] (the inline horizontal-scroll chips). Not `const`
/// because each label is a localization closure.
final kCategoryGroups = <WardrobeCategoryGroup>[
  WardrobeCategoryGroup((l) => l.catGroupTops, [
    WardrobeCategory('Tops', (l) => l.catTops),
    WardrobeCategory('T-Shirts', (l) => l.catTshirts),
    WardrobeCategory('Shirts', (l) => l.catShirts),
    WardrobeCategory('Blouses', (l) => l.catBlouses),
    WardrobeCategory('Tunics/Kurtis', (l) => l.catTunics),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupBottoms, [
    WardrobeCategory('Bottoms', (l) => l.catBottoms),
    WardrobeCategory('Pants', (l) => l.catPants),
    WardrobeCategory('Jeans', (l) => l.catJeans),
    WardrobeCategory('Skirts', (l) => l.catSkirts),
    WardrobeCategory('Shorts', (l) => l.catShorts),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupOnePiece, [
    WardrobeCategory('Dresses', (l) => l.catDresses),
    WardrobeCategory('Traditional', (l) => l.catTraditional),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupOuterwear, [
    WardrobeCategory('Outerwear', (l) => l.catOuterwear),
    WardrobeCategory('Winter', (l) => l.catWinter),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupFootwear, [
    WardrobeCategory('Shoes', (l) => l.catShoes),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupModest, [
    WardrobeCategory('Hijab', (l) => l.catHijab),
    WardrobeCategory('Scarves', (l) => l.catScarves),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupAccessories, [
    WardrobeCategory('Bags', (l) => l.catBags),
    WardrobeCategory('Eyewear', (l) => l.catEyewear),
    WardrobeCategory('Jewelry', (l) => l.catJewelry),
    WardrobeCategory('Belts', (l) => l.catBelts),
    WardrobeCategory('Hats', (l) => l.catHats),
    WardrobeCategory('Accessories', (l) => l.catAccessories),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupLifestyle, [
    WardrobeCategory('Activewear', (l) => l.catActivewear),
    WardrobeCategory('Sleepwear', (l) => l.catSleepwear),
    WardrobeCategory('Swimwear', (l) => l.catSwimwear),
    WardrobeCategory('Workwear', (l) => l.catWorkwear),
    WardrobeCategory('Party', (l) => l.catParty),
    WardrobeCategory('Travel', (l) => l.catTravel),
  ]),
  WardrobeCategoryGroup((l) => l.catGroupOther, [
    WardrobeCategory('Other', (l) => l.catOther),
  ]),
];

/// Flat list of every category (for search + lookup).
final List<WardrobeCategory> kAllCategories = [
  for (final g in kCategoryGroups) ...g.categories,
];

/// The handful of common categories shown inline as horizontal-scroll chips on
/// the Add / Categorize screens; the rest live behind the "More" picker.
const _primaryValues = [
  'Tops',
  'Bottoms',
  'Dresses',
  'Outerwear',
  'Shoes',
  'Bags',
  'Hijab',
  'Accessories',
];

List<WardrobeCategory> get primaryCategories => [
  for (final v in _primaryValues)
    kAllCategories.firstWhere((c) => c.value == v),
];

/// The taxonomy entry for a stored value, or null when it's legacy/free-text.
WardrobeCategory? categoryByValue(String? value) {
  if (value == null) return null;
  for (final c in kAllCategories) {
    if (c.value == value) return c;
  }
  return null;
}

/// Localized label for a stored category value, even one no longer in the
/// taxonomy (legacy/free-text) — falls back to the raw value capitalized.
String categoryLabel(AppLocalizations l10n, String value) {
  for (final c in kAllCategories) {
    if (c.value.toLowerCase() == value.toLowerCase()) return c.label(l10n);
  }
  return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

/// A horizontal-scroll chip row of the common categories + a "More" chip that
/// opens the full grouped picker. Used by Add Piece and Categorize so both share
/// one clean, non-messy category control (spec).
class CategoryChipsField extends StatelessWidget {
  const CategoryChipsField({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected category value, or null.
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primaries = primaryCategories;
    // Show the current selection even when it's not one of the primaries.
    final inPrimaries =
        selected != null && primaries.any((c) => c.value == selected);
    final selectedCat = categoryByValue(selected);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        children: [
          for (final c in primaries) ...[
            ChoiceChip(
              label: Text(c.label(l10n)),
              selected: selected == c.value,
              onSelected: (sel) => onChanged(sel ? c.value : null),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          // A non-primary selection (e.g. "Jeans") gets its own selected chip.
          if (!inPrimaries && selectedCat != null) ...[
            ChoiceChip(
              label: Text(selectedCat.label(l10n)),
              selected: true,
              onSelected: (_) => onChanged(null),
            ),
            const SizedBox(width: AppSpace.sm),
          ],
          ActionChip(
            avatar: const Icon(Icons.tune_rounded, size: 16),
            label: Text(l10n.catMore),
            onPressed: () async {
              final picked = await showCategoryPickerSheet(context, selected);
              if (picked != null) onChanged(picked.isEmpty ? null : picked);
            },
          ),
        ],
      ),
    );
  }
}

/// A mid-height, searchable, grouped category picker. Returns the chosen value,
/// an empty string to clear, or null if dismissed.
Future<String?> showCategoryPickerSheet(
  BuildContext context,
  String? selected,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) => _CategoryPickerSheet(selected: selected),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.selected});

  final String? selected;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final q = _query.trim().toLowerCase();

    // Filtered groups (drop groups with no matches while searching).
    final groups = [
      for (final g in kCategoryGroups)
        (
          g,
          [
            for (final c in g.categories)
              if (q.isEmpty || c.label(l10n).toLowerCase().contains(q)) c,
          ],
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xs,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.catPickerTitle, style: text.titleMedium),
                  const SizedBox(height: AppSpace.sm),
                  TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: l10n.catPickerSearchHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  0,
                  AppSpace.lg,
                  AppSpace.lg,
                ),
                children: [
                  for (final (group, cats) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpace.md,
                        bottom: AppSpace.sm,
                      ),
                      child: Text(
                        group.titleOf(l10n),
                        style: text.labelLarge?.copyWith(
                          color: AppColors.graphite,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final c in cats)
                          ChoiceChip(
                            label: Text(c.label(l10n)),
                            selected: widget.selected == c.value,
                            onSelected: (_) =>
                                Navigator.of(context).pop(c.value),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
