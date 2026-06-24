import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/flags/feature_flags.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../outfits/outfit_providers.dart';
import '../outfits/outfits_view.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import 'closet_category.dart';
import 'closet_colors.dart';
import 'closet_item_card.dart';
import 'drawers/wardrobe_view.dart';
import 'wardrobe_providers.dart';

/// The digital "Closet" (CLAUDE.md §1, §5) — three lenses on the same wardrobe:
/// a furniture-like **Wardrobe** of drawers, the polished **All Items** grid, and
/// saved **Outfits**. Upload / try-on / Supabase data are unchanged; drawers are
/// an on-device organisation layer.
class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key, this.initialTab = 0});

  /// 0 = Wardrobe (default), 1 = All Items, 2 = Outfits.
  final int initialTab;

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen>
    with WidgetsBindingObserver {
  late int _tab = widget.initialTab; // 0 = Wardrobe, 1 = All Items, 2 = Outfits

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground forces a fresh closet fetch so a cutout that
    // finished while backgrounded shows immediately (and polling resumes for any
    // still processing). Dart timers don't fire while suspended, so this is the
    // resume safety net.
    if (state == AppLifecycleState.resumed) {
      ref.read(wardrobeItemsProvider.notifier).refresh();
    }
  }

  void _openFavorites() {
    ref.read(closetCategoryProvider.notifier).select(ClosetCategory.favorites);
    setState(() => _tab = 1);
  }

  void _openOutfits() => setState(() => _tab = 2);

  /// From the Color Map: filter All Items by a colour and jump to that tab.
  void _openColor(String colorKey) {
    ref.read(closetCategoryProvider.notifier).select(ClosetCategory.all);
    ref.read(closetColorFilterProvider.notifier).set(colorKey);
    setState(() => _tab = 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.closetTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoute.wardrobeInsights),
            icon: const Icon(Icons.insights_outlined),
            tooltip: l10n.insightsTitle,
          ),
          IconButton(
            onPressed: () => context.push(AppRoute.wardrobeAdd),
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.wardrobeAdd,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _SegTabs(
              index: _tab,
              labels: [
                l10n.closetTabWardrobe,
                l10n.closetTabAllItems,
                l10n.closetTabOutfits,
              ],
              onChanged: (i) => setState(() => _tab = i),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  WardrobeView(
                    onOpenFavorites: _openFavorites,
                    onOpenOutfits: _openOutfits,
                    onOpenColor: _openColor,
                  ),
                  const _AllItemsView(),
                  const OutfitsView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dark-glass segmented control with a gradient active pill.
class _SegTabs extends StatelessWidget {
  const _SegTabs({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.sm,
        AppSpace.screenH,
        AppSpace.sm,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.easing,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Solid-accent active pill (gradient discipline, §3) — the
                    // signature gradient is reserved for the hero CTA + FAB.
                    color: i == index ? AppColors.accent : null,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: i == index ? Colors.white : AppColors.graphite,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────── All Items view ────────────────

/// The polished all-items grid (kept intact): category chips, favorites, search,
/// four states, and per-item actions.
class _AllItemsView extends ConsumerWidget {
  const _AllItemsView();

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _tryOn(BuildContext context, WidgetRef ref, WardrobeItem item) {
    ref.read(tryOnPreselectProvider.notifier).setItem(item);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
  }

  Future<void> _itemActions(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final canGiveAway = ref.read(featureEnabledProvider(FeatureFlags.giveaway));
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text(l10n.wardrobeMarkWorn),
              onTap: () => Navigator.of(ctx).pop('wear'),
            ),
            if (canGiveAway)
              ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined,
                    color: AppColors.accent),
                title: Text(l10n.giveawayCreateTitle),
                onTap: () => Navigator.of(ctx).pop('giveaway'),
              ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              title: Text(l10n.wardrobeRemove),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'wear') {
      await _markWorn(context, ref, item);
    } else if (action == 'giveaway') {
      context.push(AppRoute.giveawayCreate, extra: item);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref, item);
    }
  }

  Future<void> _markWorn(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(wardrobeRepositoryProvider).markWorn(item.id);
      ref.invalidate(wardrobeAnalyticsProvider);
      if (context.mounted) _snack(context, l10n.wardrobeWornLogged);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.wardrobeActionError);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.wardrobeDeleteTitle,
      message: l10n.wardrobeDeleteBody,
      confirmLabel: l10n.wardrobeDeleteConfirm,
      cancelLabel: l10n.wardrobeDeleteCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(wardrobeRepositoryProvider).deleteItem(item.id);
      ref.invalidate(wardrobeItemsProvider);
      ref.invalidate(wardrobeViewProvider);
      if (context.mounted) _snack(context, l10n.wardrobeDeleted);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.wardrobeDeleteError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(wardrobeViewProvider);
    final searching = ref.watch(wardrobeSearchQueryProvider).trim().isNotEmpty;
    final category = ref.watch(closetCategoryProvider);
    final favorites = ref.watch(closetFavoritesProvider);
    final colorKey = ref.watch(closetColorFilterProvider);
    final allItems = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final itemCount = allItems.length;
    final outfitCount = ref.watch(outfitsProvider).asData?.value.length ?? 0;

    List<WardrobeItem> applyFilter(List<WardrobeItem> list) {
      var result = list;
      if (category == ClosetCategory.favorites) {
        result = result.where((i) => favorites.contains(i.id)).toList();
      } else if (category != ClosetCategory.all) {
        result = result.where((i) => category.matches(i.category)).toList();
      }
      if (colorKey != null) {
        result =
            result.where((i) => itemMatchesColorFilter(i, colorKey)).toList();
      }
      return result;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenH,
            AppSpace.xs,
            AppSpace.screenH,
            AppSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.closetSubtitle(itemCount, outfitCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpace.sm),
              const _SearchField(),
            ],
          ),
        ),
        const _CategoryChips(),
        // Real-colour filter chips — only once the closet has a few distinct
        // colours (§5.2; a one-swatch row looks empty/fake).
        if (closetColorCounts(allItems).length >= 3) ...[
          const SizedBox(height: AppSpace.xs),
          ClosetColorChips(items: allItems),
        ],
        Expanded(
          child: view.when(
            skipLoadingOnReload: true,
            loading: () => SkeletonLoader.grid(aspectRatio: 0.64),
            error: (_, _) => ErrorState(
              title: l10n.wardrobeErrorTitle,
              onRetry: () => ref.invalidate(wardrobeViewProvider),
              retryLabel: l10n.commonRetry,
            ),
            data: (list) {
              final filtered = applyFilter(list);
              if (filtered.isEmpty) {
                if (searching ||
                    category != ClosetCategory.all ||
                    colorKey != null) {
                  return EmptyState(
                    icon: category == ClosetCategory.favorites
                        ? Icons.favorite_border_rounded
                        : Icons.search_off_rounded,
                    title: l10n.wardrobeSearchEmptyTitle,
                    message: l10n.wardrobeSearchEmptyMessage,
                  );
                }
                return EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: l10n.wardrobeEmptyTitle,
                  message: l10n.wardrobeEmptyMessage,
                  actionLabel: l10n.wardrobeAdd,
                  onAction: () => context.push(AppRoute.wardrobeAdd),
                );
              }
              return RefreshIndicator(
                onRefresh: () async {
                  await ref.read(wardrobeItemsProvider.notifier).refresh();
                  ref.invalidate(wardrobeViewProvider);
                },
                child: GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.screenH,
                    AppSpace.sm,
                    AppSpace.screenH,
                    bottomNavClearance(context),
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpace.lg,
                    crossAxisSpacing: AppSpace.md,
                    childAspectRatio: 0.64,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return StaggeredItem(
                      index: i,
                      child: ClosetItemCard(
                        item: item,
                        isFavorite: favorites.contains(item.id),
                        onTap: () =>
                            context.push(AppRoute.wardrobeItem, extra: item),
                        onToggleFavorite: () => ref
                            .read(closetFavoritesProvider.notifier)
                            .toggle(item.id),
                        onTryOn: () => _tryOn(context, ref, item),
                        onStyle: () => context.push(AppRoute.outfitsCreate),
                        onMenu: () => _itemActions(context, ref, item),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Horizontal category filter chips.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(closetCategoryProvider);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
        itemCount: ClosetCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final cat = ClosetCategory.values[i];
          return Center(
            child: AppChip(
              label: cat.label(l10n),
              selected: cat == selected,
              icon: cat == ClosetCategory.favorites
                  ? Icons.favorite_rounded
                  : null,
              onTap: () =>
                  ref.read(closetCategoryProvider.notifier).select(cat),
            ),
          );
        },
      ),
    );
  }
}

/// Closet search box (§2.1).
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(wardrobeSearchQueryProvider),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) =>
      ref.read(wardrobeSearchQueryProvider.notifier).setQuery(value);

  void _clear() {
    _controller.clear();
    ref.read(wardrobeSearchQueryProvider.notifier).setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onSubmitted: _submit,
      decoration: InputDecoration(
        hintText: l10n.closetSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _clear,
                tooltip: l10n.commonClear,
              ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      ),
    );
  }
}
