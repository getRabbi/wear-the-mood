import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/wardrobe_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import '../../collections/local_collections.dart';
import '../../outfits/outfit_providers.dart';
import '../wardrobe_providers.dart';
import 'closet_drawer.dart';
import 'drawer_card.dart';
import 'drawer_edit_sheet.dart';
import 'drawer_store.dart';

/// The "Wardrobe" tab — a digital wardrobe of drawers and a hanging rail, plus
/// lightweight closet-AI cards. Tapping a drawer opens it (slide-in + haptic).
class WardrobeView extends ConsumerWidget {
  const WardrobeView({
    super.key,
    required this.onOpenFavorites,
    required this.onOpenOutfits,
  });

  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenOutfits;

  void _openDrawer(BuildContext context, ClosetDrawer drawer) {
    HapticFeedback.selectionClick();
    context.push('${AppRoute.wardrobe}/drawer/${drawer.id}');
  }

  Future<void> _drawerMenu(
    BuildContext context,
    WidgetRef ref,
    ClosetDrawer drawer,
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
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.drawerEditAction),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: Text(l10n.drawerDeleteAction),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      await showDrawerEditSheet(context, existing: drawer);
    } else if (action == 'delete') {
      final ok = await showConfirmSheet(
        context,
        icon: Icons.delete_outline_rounded,
        title: l10n.drawerDeleteConfirmTitle,
        message: l10n.drawerDeleteConfirmBody,
        confirmLabel: l10n.drawerDeleteConfirm,
        cancelLabel: l10n.commonCancel,
        destructive: true,
      );
      if (ok) ref.read(closetDrawersProvider.notifier).delete(drawer.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final drawers = ref.watch(closetDrawersProvider);
    final items = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final assignments = ref.watch(closetAssignmentsProvider);
    final favorites = ref.watch(closetFavoritesProvider);
    final outfitCount = ref.watch(outfitsProvider).asData?.value.length ?? 0;

    List<String> previews(ClosetDrawer d) => itemsInDrawer(d, items, assignments)
        .map((i) => i.displayImageUrl)
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .take(3)
        .toList();
    int count(ClosetDrawer d) =>
        itemsInDrawer(d, items, assignments).length;

    final railDrawers =
        drawers.where((d) => d.kind == ClosetDrawerKind.rail).toList();
    final shelfDrawers =
        drawers.where((d) => d.kind == ClosetDrawerKind.drawer).toList();
    final unsorted = unsortedItems(items, drawers, assignments);
    final needsTidy = items
        .where((i) =>
            (i.category ?? '').trim().isEmpty || (i.title ?? '').trim().isEmpty)
        .length;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        bottomNavClearance(context),
      ),
      children: [
        // ── Closet AI ──────────────────────────────────────────────────
        _MissingPiecesCard(items: items),
        if (needsTidy > 0)
          _CleanupCard(count: needsTidy, onReview: onOpenFavorites),
        const _ColorMap(),
        const SizedBox(height: AppSpace.lg),

        // ── Hanging rail ───────────────────────────────────────────────
        if (railDrawers.isNotEmpty) ...[
          SectionHeader(title: l10n.wardrobeHangingRail),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: railDrawers.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
              itemBuilder: (_, i) {
                final d = railDrawers[i];
                return SizedBox(
                  width: 150,
                  child: DrawerCard(
                    drawer: d,
                    count: count(d),
                    previews: previews(d),
                    onTap: () => _openDrawer(context, d),
                    onMenu: () => _drawerMenu(context, ref, d),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],

        // ── Drawers & shelves ──────────────────────────────────────────
        SectionHeader(
          title: l10n.wardrobeDrawersShelves,
          actionLabel: l10n.wardrobeCreateDrawer,
          onAction: () => showDrawerEditSheet(context),
        ),
        const SizedBox(height: AppSpace.sm),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpace.md,
          crossAxisSpacing: AppSpace.md,
          childAspectRatio: 0.92,
          children: [
            for (final d in shelfDrawers)
              DrawerCard(
                drawer: d,
                count: count(d),
                previews: previews(d),
                onTap: () => _openDrawer(context, d),
                onMenu: () => _drawerMenu(context, ref, d),
              ),
            if (unsorted.isNotEmpty)
              _UnsortedCard(
                count: unsorted.length,
                previews: unsorted
                    .map((i) => i.displayImageUrl)
                    .whereType<String>()
                    .where((u) => u.isNotEmpty)
                    .take(3)
                    .toList(),
                onTap: onOpenFavorites,
              ),
            _NewDrawerCard(onTap: () => showDrawerEditSheet(context)),
          ],
        ),
        const SizedBox(height: AppSpace.lg),

        // ── Quick access ───────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _QuickCard(
                icon: Icons.favorite_rounded,
                label: l10n.wardrobeFavorites,
                count: favorites.length,
                accent: AppColors.accent,
                onTap: onOpenFavorites,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: _QuickCard(
                icon: Icons.style_rounded,
                label: l10n.wardrobeSavedOutfits,
                count: outfitCount,
                accent: AppColors.violet,
                onTap: onOpenOutfits,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────── AI cards ──────────────────

class _MissingPiecesCard extends StatelessWidget {
  const _MissingPiecesCard({required this.items});

  final List<WardrobeItem> items;

  int _matches(List<String> keys) => items.where((i) {
    final c = (i.category ?? '').toLowerCase();
    return keys.any(c.contains);
  }).length;

  @override
  Widget build(BuildContext context) {
    final tops = _matches(['top', 'shirt', 'tee', 'blouse', 'sweater', 'knit']);
    final bottoms =
        _matches(['pant', 'trouser', 'jean', 'short', 'skirt', 'legging']);
    final shoes = _matches(['shoe', 'sneaker', 'boot', 'heel', 'sandal']);

    String? message;
    final l10n = AppLocalizations.of(context);
    if (tops >= 3 && bottoms <= 1) {
      message = 'You have $tops tops but only $bottoms bottoms — '
          'add more to build complete outfits.';
    } else if (bottoms >= 2 && shoes == 0) {
      message = 'Add a pair of shoes to finish your outfits.';
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: PremiumDarkCard(
        gradientBorder: true,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: AppGradients.brand,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.closetMissingPiecesTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CleanupCard extends StatelessWidget {
  const _CleanupCard({required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.warn.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cleaning_services_outlined,
                color: AppColors.warn),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.closetCleanupTitle, style: text.titleMedium),
                  Text(l10n.closetCleanupBody(count), style: text.bodySmall),
                ],
              ),
            ),
            TextButton(onPressed: onReview, child: Text(l10n.closetCleanupReview)),
          ],
        ),
      ),
    );
  }
}

class _ColorMap extends StatelessWidget {
  const _ColorMap();

  static const _colors = <(String, Color)>[
    ('Black', Color(0xFF1A1A1A)),
    ('White', Color(0xFFF5F5F5)),
    ('Pink', AppColors.accent),
    ('Purple', AppColors.violet),
    ('Lavender', AppColors.lavender),
    ('Green', AppColors.success),
    ('Blue', Color(0xFF38BDF8)),
    ('Amber', Color(0xFFFBBF24)),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: l10n.closetColorMap),
          const SizedBox(height: AppSpace.sm),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _colors.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
              itemBuilder: (_, i) {
                final (name, color) = _colors[i];
                return SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────── small cards ────────────────

class _UnsortedCard extends StatelessWidget {
  const _UnsortedCard({
    required this.count,
    required this.previews,
    required this.onTap,
  });

  final int count;
  final List<String> previews;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reuse the drawer card look with a neutral accent.
    return DrawerCard(
      drawer: ClosetDrawer(
        id: '_unsorted',
        name: AppLocalizations.of(context).wardrobeUnsorted,
        iconKind: DrawerIconKind.box,
        accentValue: AppColors.muted.toARGB32(),
        kind: ClosetDrawerKind.drawer,
        sortOrder: 9999,
      ),
      count: count,
      previews: previews,
      onTap: onTap,
    );
  }
}

class _NewDrawerCard extends StatelessWidget {
  const _NewDrawerCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: l10n.wardrobeCreateDrawer,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassFill,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: AppColors.lavender.withValues(alpha: 0.4),
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: AppColors.lavender, size: 28),
            const SizedBox(height: AppSpace.xs),
            Text(
              l10n.wardrobeCreateDrawer,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.lavender),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadow.soft,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontSize: 14)),
                  Text('$count', style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
