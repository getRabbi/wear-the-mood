import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../outfits/outfit_providers.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import 'closet_category.dart';
import 'closet_item_card.dart';
import 'wardrobe_providers.dart';

/// The digital "Closet" (CLAUDE.md §1, §5). Image-forward grid with category
/// chips, favorites, search and all four states (§4.3), backed by
/// `GET /v1/wardrobe`. Tap a piece to open its detail; long-press / overflow to
/// log a wear or remove it. Background removal + auto-tagging (§2.2) layer in
/// server-side.
class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _tryOn(BuildContext context, WidgetRef ref, WardrobeItem item) {
    ref.read(tryOnPreselectProvider.notifier).set(item);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
  }

  /// Overflow / long-press menu for a piece: log a wear or remove it (§24).
  Future<void> _itemActions(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
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
    final itemCount = ref.watch(wardrobeItemsProvider).asData?.value.length ?? 0;
    final outfitCount = ref.watch(outfitsProvider).asData?.value.length ?? 0;

    List<WardrobeItem> applyFilter(List<WardrobeItem> list) {
      if (category == ClosetCategory.favorites) {
        return list.where((i) => favorites.contains(i.id)).toList();
      }
      if (category == ClosetCategory.all) return list;
      return list.where((i) => category.matches(i.category)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.closetTitle),
        actions: [
          IconButton(
            onPressed: () => _snack(context, l10n.closetAiOrganizeSoon),
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: l10n.closetAiOrganize,
          ),
          IconButton(
            onPressed: () => context.push(AppRoute.outfits),
            icon: const Icon(Icons.style_outlined),
            tooltip: l10n.outfitsTitle,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
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
                    if (searching || category != ClosetCategory.all) {
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
                      ref.invalidate(wardrobeItemsProvider);
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: AppSpace.lg,
                        crossAxisSpacing: AppSpace.md,
                        childAspectRatio: 0.64,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        return ClosetItemCard(
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
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal category filter chips (redesign spec).
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
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

/// Closet search box (§2.1). Searches on submit (not per keystroke) to keep the
/// query-embedding cost down; the clear button resets to browsing the closet.
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

  void _submit(String value) {
    ref.read(wardrobeSearchQueryProvider.notifier).setQuery(value);
  }

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
