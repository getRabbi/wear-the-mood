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
import 'wardrobe_providers.dart';

/// The digital wardrobe ("digital almira", CLAUDE.md §1, §5). Image-forward grid
/// with all four states (§4.3), backed by `GET /v1/wardrobe`. Long-press a tile
/// to remove it, or use the add button to capture/upload a new piece (§8).
/// Background removal + auto-tagging (§2.2) layer on server-side later.
class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.wardrobeDeleteTitle),
        content: Text(l10n.wardrobeDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.wardrobeDeleteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.wardrobeDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(wardrobeRepositoryProvider).deleteItem(item.id);
      ref.invalidate(wardrobeItemsProvider);
      if (context.mounted) _snack(context, l10n.wardrobeDeleted);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.wardrobeDeleteError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(wardrobeItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navWardrobe),
        actions: [
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
        child: items.when(
          loading: () => const _ShimmerGrid(),
          error: (_, _) => ErrorState(
            title: l10n.wardrobeErrorTitle,
            onRetry: () => ref.invalidate(wardrobeItemsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: l10n.wardrobeEmptyTitle,
                  message: l10n.wardrobeEmptyMessage,
                  actionLabel: l10n.wardrobeAdd,
                  onAction: () => context.push(AppRoute.wardrobeAdd),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(wardrobeItemsProvider),
                  child: _WardrobeGrid(
                    items: list,
                    onLongPress: (item) => _confirmDelete(context, ref, item),
                  ),
                ),
        ),
      ),
    );
  }
}

class _WardrobeGrid extends StatelessWidget {
  const _WardrobeGrid({required this.items, required this.onLongPress});

  final List<WardrobeItem> items;
  final void Function(WardrobeItem item) onLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.66,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        final tile = OutfitTile(
          imageUrl: item.displayImageUrl ?? '',
          label: item.title,
          onLongPress: () => onLongPress(item),
        );
        if (!item.isProcessingCutout) return tile;
        return Stack(
          children: [
            tile,
            const Positioned(
              top: AppSpace.sm,
              left: AppSpace.sm,
              child: _ProcessingBadge(),
            ),
          ],
        );
      },
    );
  }
}

/// Shown on a tile while its background-removal cutout is still generating (§2.2).
class _ProcessingBadge extends StatelessWidget {
  const _ProcessingBadge();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Text(
            l10n.wardrobeProcessing,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.66,
      ),
      itemCount: 6,
      itemBuilder: (context, _) => LoadingShimmer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }
}
