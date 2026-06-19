import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import '../wardrobe/closet_category.dart';
import '../wardrobe/wardrobe_providers.dart';

/// Outfit detail (Issue 9): tapping a saved outfit opens THIS — a flat-lay grid
/// of every piece in the look — not the editor. Edit and Try-on are deliberate
/// actions here (an AppBar button / a CTA), never the default tap. Item images
/// are the closet's durable cutout/image URLs (resolved from the loaded closet).
class OutfitDetailScreen extends ConsumerWidget {
  const OutfitDetailScreen({super.key, required this.outfit});

  final Outfit outfit;

  void _tryOnFullLook(
    BuildContext context,
    WidgetRef ref,
    List<WardrobeItem> items,
  ) {
    if (items.isEmpty) return;
    ref.read(tryOnPreselectProvider.notifier).setItems(items);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
    context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final closet = ref.watch(wardrobeItemsProvider);
    final name = (outfit.name?.trim().isNotEmpty ?? false)
        ? outfit.name!.trim()
        : l10n.outfitsUntitled;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          // Edit is a deliberate action — not the default tap (Issue 9).
          IconButton(
            tooltip: l10n.outfitEditAction,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push(AppRoute.outfitsCreate, extra: outfit),
          ),
        ],
      ),
      body: closet.when(
        loading: () => SkeletonLoader.grid(aspectRatio: 0.8),
        error: (_, _) => ErrorState(
          title: l10n.outfitsErrorTitle,
          onRetry: () => ref.invalidate(wardrobeItemsProvider),
          retryLabel: l10n.commonRetry,
        ),
        data: (closetItems) {
          final byId = {for (final i in closetItems) i.id: i};
          // Preserve the outfit's saved order; skip pieces removed from the closet.
          final items = [
            for (final id in outfit.itemIds)
              if (byId[id] != null) byId[id]!,
          ];
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.checkroom_outlined,
              title: l10n.outfitDetailMissingTitle,
              message: l10n.outfitDetailMissingBody,
              actionLabel: l10n.outfitEditAction,
              onAction: () =>
                  context.push(AppRoute.outfitsCreate, extra: outfit),
            );
          }
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.screenH,
                    AppSpace.md,
                    AppSpace.screenH,
                    AppSpace.md,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpace.md,
                    crossAxisSpacing: AppSpace.md,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final label = closetItemName(item);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: GarmentTile(
                            imageUrl: item.displayImageUrl ?? '',
                          ),
                        ),
                        if (label != null) ...[
                          const SizedBox(height: AppSpace.xs),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: PrimaryButton(
                    label: l10n.outfitTryFullLook,
                    icon: Icons.auto_awesome,
                    onPressed: () => _tryOnFullLook(context, ref, items),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
