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

/// Body-only saved-outfits grid (no Scaffold) — reused by the Closet "Outfits"
/// tab. Try on / edit happen from the create flow; long-press removes.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outfits = ref.watch(outfitsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenH,
            AppSpace.sm,
            AppSpace.screenH,
            AppSpace.sm,
          ),
          child: PrimaryButton(
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
                        final name = (outfit.name?.trim().isNotEmpty ?? false)
                            ? outfit.name!.trim()
                            : l10n.outfitsUntitled;
                        return Stack(
                          children: [
                            OutfitTile(
                              imageUrl: outfit.coverImageUrl ?? '',
                              label: name,
                              onLongPress: () =>
                                  _confirmDelete(context, ref, outfit),
                            ),
                            Positioned(
                              top: AppSpace.sm,
                              left: AppSpace.sm,
                              child: _CountBadge(count: outfit.itemCount),
                            ),
                          ],
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
        color: AppColors.scrim,
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
