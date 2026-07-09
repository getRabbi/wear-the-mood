import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/collections/local_collections.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Smart Closet (board 02, P3) — the real closet on the existing wardrobe
/// providers: signed R2/Supabase image URLs on [FabricTile] (stable cache
/// keys), live stat cells (§3.1 — Items→All, Outfits→Maker, Favorites→filter,
/// Categories→sheet), category chips + filter sheet, and the four §0.4 states.
/// Favorites are the device-local [closetFavoritesProvider] (no schema change).
class WtmClosetScreen extends ConsumerWidget {
  const WtmClosetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final itemsAsync = ref.watch(wardrobeItemsProvider);
    final category = ref.watch(closetCategoryProvider);
    final favorites = ref.watch(closetFavoritesProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: WtmColors.gold,
        backgroundColor: WtmColors.panel,
        onRefresh: () => ref.read(wardrobeItemsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            wtmNavClearance,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.wtmClosetTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WtmType.h1,
                  ),
                ),
                WtmIconButton(
                  WtmGlyph.plus,
                  semanticLabel: l10n.wtmClosetAddLabel,
                  onTap: () => context.push(AppRoute.wtmClosetAdd),
                ),
                const SizedBox(width: WtmSpace.s4),
                WtmIconButton(
                  WtmGlyph.search,
                  semanticLabel: l10n.wtmClosetSearchLabel,
                  onTap: () =>
                      context.push('${AppRoute.wtmSearch}?scope=closet'),
                ),
              ],
            ),
            const SizedBox(height: WtmSpace.s16),
            // .when + skipLoadingOnReload, like the shipped closet — under
            // riverpod 3's auto-retry a failed load cycles through reloading
            // states, and this keeps rendering the error (with Retry) instead
            // of bouncing back to shimmer.
            ...itemsAsync.when<List<Widget>>(
              skipLoadingOnReload: true,
              loading: _loading,
              error: (_, _) => [
                const SizedBox(height: WtmSpace.s22),
                WtmErrorState(
                  title: l10n.wtmClosetErrorTitle,
                  message: l10n.errorGenericTitle,
                  retryLabel: l10n.commonRetry,
                  onRetry: () => ref.invalidate(wardrobeItemsProvider),
                ),
              ],
              data: (items) =>
                  _content(context, ref, l10n, items, category, favorites),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Loading: shimmer over fabric-swatch placeholders (§0.4). ----
  List<Widget> _loading() {
    return [
      const LoadingShimmer(width: double.infinity, height: 74),
      const SizedBox(height: WtmSpace.s14),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 3 / 4,
        children: [
          for (var i = 0; i < 9; i++)
            Stack(
              fit: StackFit.expand,
              children: [
                FabricTile(swatchIndex: i, aspectRatio: null),
                const Positioned.fill(
                  child: LoadingShimmer(
                    borderRadius:
                        BorderRadius.all(Radius.circular(WtmRadius.tile)),
                  ),
                ),
              ],
            ),
        ],
      ),
    ];
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    List<WardrobeItem> items,
    ClosetCategory category,
    Set<String> favorites,
  ) {
    if (items.isEmpty) {
      return [
        const SizedBox(height: WtmSpace.s22),
        WtmEmptyState(
          glyph: WtmGlyph.hanger,
          title: l10n.wtmClosetEmptyTitle,
          message: l10n.wtmClosetEmptyMessage,
          ctaLabel: l10n.wtmClosetEmptyCta,
          onCta: () => context.push(AppRoute.wtmClosetAdd),
        ),
      ];
    }

    final filtered = switch (category) {
      ClosetCategory.favorites =>
        [for (final i in items) if (favorites.contains(i.id)) i],
      _ => [for (final i in items) if (category.matches(i.category)) i],
    };
    final categoriesUsed = {
      for (final i in items)
        for (final c in ClosetCategory.values)
          if (c != ClosetCategory.all &&
              c != ClosetCategory.favorites &&
              c.matches(i.category))
            c,
    };
    final outfitsCount =
        ref.watch(outfitsProvider).asData?.value.length;
    void pick(ClosetCategory c) =>
        ref.read(closetCategoryProvider.notifier).select(c);

    return [
      // Stat cells are tap targets (§3.1/§8).
      Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
        decoration: BoxDecoration(
          gradient: WtmGradients.cardFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: Row(
          children: [
            _Stat(
              '${items.length}',
              l10n.wtmClosetStatItems,
              onTap: () => pick(ClosetCategory.all),
            ),
            _statDivider,
            _Stat(
              outfitsCount?.toString() ?? '—',
              l10n.wtmClosetStatOutfits,
              onTap: () => context.push(AppRoute.wtmOutfits),
            ),
            _statDivider,
            _Stat(
              '${favorites.where((id) => items.any((i) => i.id == id)).length}',
              l10n.wtmClosetStatFavorites,
              on: category == ClosetCategory.favorites,
              onTap: () => pick(
                category == ClosetCategory.favorites
                    ? ClosetCategory.all
                    : ClosetCategory.favorites,
              ),
            ),
            _statDivider,
            _Stat(
              '${categoriesUsed.length}',
              l10n.wtmClosetStatCategories,
              onTap: () => _categoriesSheet(context, l10n, pick),
            ),
          ],
        ),
      ),
      const SizedBox(height: WtmSpace.s14),
      Row(
        children: [
          Expanded(
            child: WtmChipRow(
              children: [
                for (final c in ClosetCategory.values)
                  if (c != ClosetCategory.favorites)
                    WtmChip(
                      label: c.label(l10n),
                      on: category == c,
                      onTap: () => pick(c),
                    ),
              ],
            ),
          ),
          const SizedBox(width: WtmSpace.s8),
          WtmIconButton(
            WtmGlyph.filter,
            semanticLabel: l10n.wtmClosetFilterTitle,
            onTap: () => _filterSheet(context, l10n, ref),
          ),
        ],
      ),
      const SizedBox(height: WtmSpace.s14),
      if (filtered.isEmpty)
        WtmEmptyState(
          glyph: category == ClosetCategory.favorites
              ? WtmGlyph.heart
              : WtmGlyph.hanger,
          title: l10n.emptyGenericTitle,
          message: l10n.wtmClosetEmptyMessage,
          ctaLabel: l10n.wtmClosetEmptyCta,
          onCta: () => context.push(AppRoute.wtmClosetAdd),
        )
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 3 / 4,
          children: [
            for (final (i, item) in filtered.indexed)
              FabricTile(
                imageUrl: item.displayImageUrl,
                swatchIndex: i,
                aspectRatio: null,
                fit: BoxFit.contain, // cutouts float on the swatch
                semanticLabel: closetCardLabel(l10n, item),
                onTap: () => context.push(AppRoute.wtmClosetItem, extra: item),
              ),
          ],
        ),
    ];
  }

  Future<void> _categoriesSheet(
    BuildContext context,
    AppLocalizations l10n,
    void Function(ClosetCategory) pick,
  ) {
    return showWtmSheet(
      context,
      title: l10n.wtmClosetStatCategories,
      children: [
        for (final (i, c) in ClosetCategory.values.indexed)
          if (c != ClosetCategory.all && c != ClosetCategory.favorites) ...[
            if (i > 1) const SizedBox(height: 9),
            WtmRow(
              glyph: WtmGlyph.hanger,
              title: c.label(l10n),
              onTap: () {
                Navigator.of(context).pop();
                pick(c);
              },
            ),
          ],
      ],
    );
  }

  Future<void> _filterSheet(
    BuildContext context,
    AppLocalizations l10n,
    WidgetRef ref,
  ) {
    return showWtmSheet(
      context,
      title: l10n.wtmClosetFilterTitle,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final selected = ref.watch(closetCategoryProvider);
            return Wrap(
              spacing: WtmSpace.s6,
              runSpacing: WtmSpace.s6,
              children: [
                for (final c in ClosetCategory.values)
                  WtmChip(
                    label: c.label(l10n),
                    on: selected == c,
                    onTap: () {
                      ref.read(closetCategoryProvider.notifier).select(c);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

const _statDivider = SizedBox(
  height: 26,
  child: VerticalDivider(color: WtmColors.lineSoft, width: 1),
);

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {required this.onTap, this.on = false});

  final String value;
  final String label;
  final VoidCallback onTap;

  /// Gold accent when this stat is the active filter (Favorites).
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: '$value $label',
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(
              children: [
                Text(
                  value,
                  style: on
                      ? WtmType.h2.copyWith(color: WtmColors.gold)
                      : WtmType.h2,
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  style: WtmType.micro.copyWith(
                    fontSize: 8.5,
                    letterSpacing: 1.36,
                    color: on ? WtmColors.goldDim : WtmColors.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
