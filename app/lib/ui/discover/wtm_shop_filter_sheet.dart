import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/domain/product_filters.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Opens the Discover filter sheet (DISCOVER §11.2).
///
/// A bottom sheet rather than a permanent chip row: Discover shows only a
/// compact `Filters · N` indicator, never a filter bar taking up the top of the
/// screen (§26.1).
Future<void> showWtmShopFilterSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  // Edited locally and applied on confirm, so half-set filters never refetch
  // the feed while the user is still choosing.
  late ProductFilters _draft = ref.read(productFiltersProvider);

  void _apply() {
    ref.read(productFiltersProvider.notifier).apply(_draft);
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.filterApplied,
          properties: {
            DiscoverAnalyticsProps.filterCount: _draft.activeCount,
            // The COUNT and which dimensions, never the user's literal budget.
            DiscoverAnalyticsProps.filterKeys: [
              if (_draft.category != null) 'category',
              if (_draft.colors.isNotEmpty) 'color',
              if (_draft.sizes.isNotEmpty) 'size',
              if (_draft.minPriceMinor != null || _draft.maxPriceMinor != null)
                'price',
              if (_draft.tryOnReady) 'try_on',
              if (_draft.discounted) 'discount',
            ].join(','),
          },
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keyboard-safe: the sheet lifts above the inset so nothing it contains is
    // ever hidden behind a keyboard (§41 "no keyboard overlap").
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: WtmColors.panel,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(WtmRadius.sheetTop),
          ),
          border: Border(top: BorderSide(color: WtmColors.line)),
        ),
        padding: const EdgeInsets.fromLTRB(
          WtmSpace.s18,
          WtmSpace.s14,
          WtmSpace.s18,
          WtmSpace.s22,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l10n.wtmShopFilter, style: WtmType.h2),
                    const Spacer(),
                    // Reset is always available, so a user can never get stuck
                    // behind a filter set they cannot remember (§11.2).
                    GhostButton(
                      label: l10n.wtmShopFilterReset,
                      onPressed: () =>
                          setState(() => _draft = const ProductFilters()),
                    ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                _Section(label: l10n.wtmShopFilterCategory),
                WtmChipRow(
                  children: [
                    for (final category in _categories)
                      WtmChip(
                        label: category,
                        on: _draft.category == category,
                        onTap: () => setState(() {
                          _draft = _draft.category == category
                              ? _draft.copyWith(clearCategory: true)
                              : _draft.copyWith(category: category);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                _Section(label: l10n.wtmShopFilterSize),
                WtmChipRow(
                  children: [
                    for (final size in _sizes)
                      WtmChip(
                        label: size,
                        on: _draft.sizes.contains(size),
                        onTap: () => setState(() {
                          final next = [..._draft.sizes];
                          next.contains(size)
                              ? next.remove(size)
                              : next.add(size);
                          _draft = _draft.copyWith(sizes: next);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                _Section(label: l10n.wtmShopFilterColor),
                WtmChipRow(
                  children: [
                    for (final color in _colors)
                      WtmChip(
                        label: color,
                        on: _draft.colors.contains(color),
                        onTap: () => setState(() {
                          final next = [..._draft.colors];
                          next.contains(color)
                              ? next.remove(color)
                              : next.add(color);
                          _draft = _draft.copyWith(colors: next);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                WtmChipRow(
                  children: [
                    WtmChip(
                      label: l10n.wtmShopFilterTryOn,
                      on: _draft.tryOnReady,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          tryOnReady: !_draft.tryOnReady,
                        ),
                      ),
                    ),
                    WtmChip(
                      label: l10n.wtmShopFilterDiscount,
                      on: _draft.discounted,
                      onTap: () => setState(
                        () => _draft = _draft.copyWith(
                          discounted: !_draft.discounted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s22),

                GradientCta(label: l10n.wtmShopFilterApply, onPressed: _apply),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter vocabularies.
///
/// Hard-coded for this release because the catalog is not seeded yet and an
/// empty, server-derived facet list would render an empty sheet. These are
/// category and attribute NAMES, not copy, so they are not l10n strings; when
/// the catalog lands they should come from its facets instead.
const _categories = [
  'Dresses',
  'Tops',
  'Bottoms',
  'Outerwear',
  'Shoes',
  'Bags',
];
const _sizes = ['XS', 'S', 'M', 'L', 'XL'];
const _colors = ['Black', 'White', 'Blue', 'Green', 'Red', 'Neutral'];

class _Section extends StatelessWidget {
  const _Section({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WtmSpace.s8),
    child: EyebrowLabel(label),
  );
}
