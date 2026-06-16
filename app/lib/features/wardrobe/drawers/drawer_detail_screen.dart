import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/wardrobe_item.dart';
import '../../../data/repositories/wardrobe_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../collections/local_collections.dart';
import '../../shell/shell_providers.dart';
import '../../tryon/tryon_preselect.dart';
import '../closet_category.dart';
import '../closet_item_card.dart';
import '../wardrobe_providers.dart';
import 'closet_drawer.dart';
import 'drawer_edit_sheet.dart';
import 'drawer_store.dart';

enum _Sort { recent, worn, favorites }

/// A single drawer opened: its items, with search-within, sort, and per-item
/// actions (try-on, style, move to another drawer). The 2.5D "open" feel comes
/// from the slide-in route + a soft accent header.
class DrawerDetailScreen extends ConsumerStatefulWidget {
  const DrawerDetailScreen({super.key, required this.drawerId});

  final String drawerId;

  @override
  ConsumerState<DrawerDetailScreen> createState() => _DrawerDetailScreenState();
}

class _DrawerDetailScreenState extends ConsumerState<DrawerDetailScreen> {
  String _query = '';
  _Sort _sort = _Sort.recent;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _editDrawer(ClosetDrawer drawer) =>
      showDrawerEditSheet(context, existing: drawer);

  Future<void> _deleteDrawer(ClosetDrawer drawer) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.drawerDeleteConfirmTitle,
      message: l10n.drawerDeleteConfirmBody,
      confirmLabel: l10n.drawerDeleteConfirm,
      cancelLabel: l10n.commonCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    ref.read(closetDrawersProvider.notifier).delete(drawer.id);
    if (mounted) context.pop();
  }

  Future<void> _moveItem(WardrobeItem item) async {
    final l10n = AppLocalizations.of(context);
    final drawers = ref.read(closetDrawersProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.sm,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Text(l10n.drawerMoveTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final d in drawers)
              ListTile(
                leading: Icon(d.icon, color: d.accent),
                title: Text(d.name),
                onTap: () => Navigator.of(ctx).pop(d.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    ref.read(closetAssignmentsProvider.notifier).assign(item.id, picked);
    final name = ref.read(closetDrawersProvider.notifier).byId(picked)?.name ?? '';
    _snack(l10n.drawerAssigned(name));
  }

  Future<void> _itemMenu(WardrobeItem item) async {
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(l10n.drawerMoveTitle),
              onTap: () => Navigator.of(ctx).pop('move'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text(l10n.wardrobeMarkWorn),
              onTap: () => Navigator.of(ctx).pop('wear'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: Text(l10n.wardrobeRemove),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'move':
        await _moveItem(item);
      case 'wear':
        try {
          await ref.read(wardrobeRepositoryProvider).markWorn(item.id);
          ref.invalidate(wardrobeAnalyticsProvider);
          if (mounted) _snack(l10n.wardrobeWornLogged);
        } on ApiException {
          if (mounted) _snack(l10n.wardrobeActionError);
        }
      case 'delete':
        try {
          await ref.read(wardrobeRepositoryProvider).deleteItem(item.id);
          ref.invalidate(wardrobeItemsProvider);
          ref.invalidate(wardrobeViewProvider);
          if (mounted) _snack(l10n.wardrobeDeleted);
        } on ApiException {
          if (mounted) _snack(l10n.wardrobeDeleteError);
        }
    }
  }

  List<WardrobeItem> _sorted(List<WardrobeItem> items, Set<String> favorites) {
    switch (_sort) {
      case _Sort.favorites:
        final favs = items.where((i) => favorites.contains(i.id)).toList();
        final rest = items.where((i) => !favorites.contains(i.id)).toList();
        return [...favs, ...rest];
      case _Sort.worn:
      // Per-item wear counts aren't exposed yet (TODO): keep recent order.
      case _Sort.recent:
        return items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final drawer = ref.watch(
      closetDrawersProvider.select((list) {
        for (final d in list) {
          if (d.id == widget.drawerId) return d;
        }
        return null;
      }),
    );

    if (drawer == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.wardrobeUnsorted)),
      );
    }

    final allItems = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final assignments = ref.watch(closetAssignmentsProvider);
    final favorites = ref.watch(closetFavoritesProvider);

    var items = itemsInDrawer(drawer, allItems, assignments);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      items = items.where((i) {
        final name = (closetItemName(i) ?? '').toLowerCase();
        final cat = (i.category ?? '').toLowerCase();
        return name.contains(q) || cat.contains(q);
      }).toList();
    }
    items = _sorted(items, favorites);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(drawer.icon, color: drawer.accent, size: 20),
            const SizedBox(width: AppSpace.sm),
            Flexible(child: Text(drawer.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.drawerEditAction,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editDrawer(drawer),
          ),
          IconButton(
            tooltip: l10n.drawerDeleteAction,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _deleteDrawer(drawer),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Accent header + style action.
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpace.screenH,
                AppSpace.sm,
                AppSpace.screenH,
                0,
              ),
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    drawer.accent.withValues(alpha: 0.22),
                    drawer.accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wardrobeItemsCount(items.length),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  SecondaryButton(
                    label: l10n.drawerStyleThis,
                    icon: Icons.auto_awesome,
                    expand: false,
                    onPressed: () => _snack(l10n.drawerStyleThisSoon),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screenH,
                AppSpace.sm,
                AppSpace.screenH,
                0,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: l10n.drawerDetailSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
                children: [
                  for (final s in _Sort.values) ...[
                    Center(
                      child: AppChip(
                        label: switch (s) {
                          _Sort.recent => l10n.drawerSortRecent,
                          _Sort.worn => l10n.drawerSortWorn,
                          _Sort.favorites => l10n.drawerSortFavorites,
                        },
                        selected: s == _sort,
                        onTap: () => setState(() => _sort = s),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                  ],
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? EmptyState(
                      icon: drawer.icon,
                      title: l10n.drawerEmptyTitle,
                      message: l10n.drawerEmptyMessage(drawer.name),
                      actionLabel: l10n.drawerAddItem,
                      onAction: () => context.push(
                        AppRoute.wardrobeAdd,
                        extra: drawer.id,
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.screenH,
                        AppSpace.sm,
                        AppSpace.screenH,
                        AppSpace.xl,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: AppSpace.lg,
                        crossAxisSpacing: AppSpace.md,
                        childAspectRatio: 0.64,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return ClosetItemCard(
                          item: item,
                          isFavorite: favorites.contains(item.id),
                          onTap: () =>
                              context.push(AppRoute.wardrobeItem, extra: item),
                          onToggleFavorite: () => ref
                              .read(closetFavoritesProvider.notifier)
                              .toggle(item.id),
                          onTryOn: () {
                            ref.read(tryOnPreselectProvider.notifier).setItem(item);
                            ref
                                .read(shellTabProvider.notifier)
                                .select(ShellTabs.tryOn);
                          },
                          onStyle: () => context.push(AppRoute.outfitsCreate),
                          onMenu: () => _itemMenu(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoute.wardrobeAdd, extra: drawer.id),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.drawerAddItem),
      ),
    );
  }
}
