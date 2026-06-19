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
import '../collections/local_collections.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'outfit_collage.dart';
import 'outfit_providers.dart';

/// Body-only saved-outfits grid (no Scaffold) — reused by the Closet "Outfits"
/// tab. Cards show a real piece-collage preview; tap to edit the set, heart to
/// favorite, long-press for try-on / delete.
class OutfitsView extends ConsumerWidget {
  const OutfitsView({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Outfit outfit,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.outfitsDeleteTitle,
      message: l10n.outfitsDeleteBody,
      confirmLabel: l10n.outfitsDeleteConfirm,
      cancelLabel: l10n.outfitsDeleteCancel,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(outfitRepositoryProvider).deleteOutfit(outfit.id);
      ref.invalidate(outfitsProvider);
    } on ApiException {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.outfitsDeleteError)));
      }
    }
  }

  /// Stack the outfit's pieces into the Try-On Studio (MoodMirror 2D stays free).
  void _tryOnFullLook(WidgetRef ref, Outfit outfit) {
    final closet = ref.read(wardrobeItemsProvider).asData?.value ?? const [];
    final ids = outfit.itemIds.toSet();
    final items = [for (final i in closet) if (ids.contains(i.id)) i];
    if (items.isEmpty) return;
    ref.read(tryOnPreselectProvider.notifier).setItems(items);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
  }

  Future<void> _openActions(
    BuildContext context,
    WidgetRef ref,
    Outfit outfit,
  ) async {
    final l10n = AppLocalizations.of(context);
    final isFav = ref.read(outfitFavoritesProvider).contains(outfit.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(l10n.outfitTryFullLook),
              onTap: () => Navigator.pop(ctx, 'tryon'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.outfitEditAction),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(
                isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? AppColors.accent : null,
              ),
              title: Text(isFav ? l10n.outfitUnfavorite : l10n.outfitFavorite),
              onTap: () => Navigator.pop(ctx, 'favorite'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: Text(l10n.outfitsDeleteConfirm),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'tryon':
        _tryOnFullLook(ref, outfit);
      case 'edit':
        context.push(AppRoute.outfitsCreate, extra: outfit);
      case 'favorite':
        ref.read(outfitFavoritesProvider.notifier).toggle(outfit.id);
      case 'delete':
        await _confirmDelete(context, ref, outfit);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outfits = ref.watch(outfitsProvider);
    final favorites = ref.watch(outfitFavoritesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenH,
            AppSpace.sm,
            AppSpace.screenH,
            AppSpace.sm,
          ),
          // The one signature-gradient hero action on this tab (§5.2).
          child: HeroButton(
            label: l10n.outfitsCreate,
            icon: Icons.add_rounded,
            onPressed: () => context.push(AppRoute.outfitsCreate),
          ),
        ),
        Expanded(
          child: outfits.when(
            loading: () => SkeletonLoader.grid(aspectRatio: 0.66),
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
                        mainAxisSpacing: AppSpace.md,
                        crossAxisSpacing: AppSpace.md,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final outfit = list[i];
                        return OutfitCollageCard(
                          outfit: outfit,
                          isFavorite: favorites.contains(outfit.id),
                          // Tap shows the full look; Edit is deliberate (Issue 9).
                          onTap: () => context.push(
                            AppRoute.outfitsDetail,
                            extra: outfit,
                          ),
                          onToggleFavorite: () => ref
                              .read(outfitFavoritesProvider.notifier)
                              .toggle(outfit.id),
                          onLongPress: () =>
                              _openActions(context, ref, outfit),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
