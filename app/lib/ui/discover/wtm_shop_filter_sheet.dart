import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../features/discover/application/product_feed.dart';
import '../../data/models/facets.dart';
import '../../data/repositories/discover_repository.dart';
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
    // Server facets when we have them, curated list when we do not. An empty
    // server answer (a region with no catalog) falls back too, so the sheet is
    // never blank.
    final served = ref.watch(catalogFacetsProvider).asData?.value;
    final facets = (served == null || served.isEmpty) ? fallbackFacets : served;
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
                    // Expanded, not Spacer: at 2x text on a 320dp phone the
                    // title and Reset together overflowed the header by 83px.
                    // The title is the part that can afford to ellipsise.
                    Expanded(
                      child: Text(
                        l10n.wtmShopFilter,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.h2,
                      ),
                    ),
                    const SizedBox(width: WtmSpace.s10),
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
                    for (final facet in facets.categories)
                      WtmChip(
                        label: facet.label,
                        on: _draft.category == facet.value,
                        onTap: () => setState(() {
                          _draft = _draft.category == facet.value
                              ? _draft.copyWith(clearCategory: true)
                              : _draft.copyWith(category: facet.value);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                _Section(label: l10n.wtmShopFilterSize),
                WtmChipRow(
                  children: [
                    for (final facet in facets.sizes)
                      WtmChip(
                        label: facet.label,
                        on: _draft.sizes.contains(facet.value),
                        onTap: () => setState(() {
                          final next = [..._draft.sizes];
                          next.contains(facet.value)
                              ? next.remove(facet.value)
                              : next.add(facet.value);
                          _draft = _draft.copyWith(sizes: next);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                _Section(label: l10n.wtmShopFilterColor),
                WtmChipRow(
                  children: [
                    for (final facet in facets.colors)
                      WtmChip(
                        label: facet.label,
                        on: _draft.colors.contains(facet.value),
                        onTap: () => setState(() {
                          final next = [..._draft.colors];
                          next.contains(facet.value)
                              ? next.remove(facet.value)
                              : next.add(facet.value);
                          _draft = _draft.copyWith(colors: next);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),

                WtmChipRow(
                  children: [
                    // Offered only when the catalog actually has such products.
                    // A toggle that can only ever return nothing is worse than
                    // no toggle at all.
                    if (facets.tryOnAvailable)
                      WtmChip(
                        label: l10n.wtmShopFilterTryOn,
                        on: _draft.tryOnReady,
                        onTap: () => setState(
                          () => _draft = _draft.copyWith(
                            tryOnReady: !_draft.tryOnReady,
                          ),
                        ),
                      ),
                    if (facets.discountAvailable)
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

/// Server-derived filter vocabularies for the currently servable catalog
/// (§11.2). Null while loading or when the backend cannot answer.
final catalogFacetsProvider = FutureProvider.autoDispose<CatalogFacets?>((ref) {
  return ref.watch(discoverRepositoryProvider).facets();
});

/// The curated fallback — ONLY for a backend that cannot answer, or a region
/// with no catalog.
///
/// This was the PRIMARY source before facets existed; it is now the last
/// resort. A hard-coded list inevitably offers filters that match nothing,
/// which is the exact failure server-derived facets exist to prevent — but an
/// empty filter sheet is a dead end, so something has to be here.
///
/// Values are canonical (what the API filters on); labels are display text.
const fallbackFacets = CatalogFacets(
  categories: [
    FacetValue(value: 'dresses', label: 'Dresses'),
    FacetValue(value: 'tops', label: 'Tops'),
    FacetValue(value: 'bottoms', label: 'Bottoms'),
    FacetValue(value: 'outerwear', label: 'Outerwear'),
  ],
  sizes: [
    FacetValue(value: 'XS', label: 'XS'),
    FacetValue(value: 'S', label: 'S'),
    FacetValue(value: 'M', label: 'M'),
    FacetValue(value: 'L', label: 'L'),
    FacetValue(value: 'XL', label: 'XL'),
  ],
  colors: [
    FacetValue(value: 'black', label: 'Black'),
    FacetValue(value: 'white', label: 'White'),
    FacetValue(value: 'blue', label: 'Blue'),
    FacetValue(value: 'green', label: 'Green'),
    FacetValue(value: 'neutral', label: 'Neutral'),
  ],
  tryOnAvailable: true,
  discountAvailable: true,
);

class _Section extends StatelessWidget {
  const _Section({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: WtmSpace.s8),
    child: EyebrowLabel(label),
  );
}
