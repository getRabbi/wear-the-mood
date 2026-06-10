import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/repositories/outfit_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'outfit_providers.dart';

/// Saved outfits — the user's reusable looks (CLAUDE.md §5). Image-forward grid
/// with all four states (§4.3); long-press to remove, FAB to build a new one.
class OutfitsScreen extends ConsumerWidget {
  const OutfitsScreen({super.key});

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Outfit outfit,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.outfitsDeleteTitle),
        content: Text(l10n.outfitsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.outfitsDeleteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.outfitsDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(outfitRepositoryProvider).deleteOutfit(outfit.id);
      ref.invalidate(outfitsProvider);
      if (context.mounted) _snack(context, l10n.outfitsDeleted);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.outfitsDeleteError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outfits = ref.watch(outfitsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.outfitsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoute.outfitsCreate),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.outfitsCreate),
      ),
      body: SafeArea(
        child: outfits.when(
          loading: () => const _ShimmerGrid(),
          error: (_, _) => ErrorState(
            title: l10n.outfitsErrorTitle,
            onRetry: () => ref.invalidate(outfitsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.style_outlined,
                  title: l10n.outfitsEmptyTitle,
                  message: l10n.outfitsEmptyMessage,
                  actionLabel: l10n.outfitsCreate,
                  onAction: () => context.push(AppRoute.outfitsCreate),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(outfitsProvider),
                  child: _OutfitGrid(
                    outfits: list,
                    onLongPress: (o) => _confirmDelete(context, ref, o),
                  ),
                ),
        ),
      ),
    );
  }
}

class _OutfitGrid extends StatelessWidget {
  const _OutfitGrid({required this.outfits, required this.onLongPress});

  final List<Outfit> outfits;
  final void Function(Outfit outfit) onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.xxl + AppSpace.lg, // clear the FAB
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.66,
      ),
      itemCount: outfits.length,
      itemBuilder: (context, i) {
        final outfit = outfits[i];
        final name = (outfit.name?.trim().isNotEmpty ?? false)
            ? outfit.name!.trim()
            : l10n.outfitsUntitled;
        return Stack(
          children: [
            OutfitTile(
              imageUrl: outfit.coverImageUrl ?? '',
              label: name,
              onLongPress: () => onLongPress(outfit),
            ),
            Positioned(
              top: AppSpace.sm,
              left: AppSpace.sm,
              child: _CountBadge(count: outfit.itemCount),
            ),
          ],
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.checkroom_rounded, size: 13, color: Colors.white),
          const SizedBox(width: AppSpace.xs),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
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
