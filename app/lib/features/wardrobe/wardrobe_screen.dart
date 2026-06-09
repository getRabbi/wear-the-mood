import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'wardrobe_providers.dart';

/// The digital wardrobe ("digital almira", CLAUDE.md §1, §5). Image-forward grid
/// with all four states (§4.3). Backed by placeholder data until the wardrobe
/// backend + image upload (§8) land.
class WardrobeScreen extends ConsumerWidget {
  const WardrobeScreen({super.key});

  void _comingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            onPressed: () => _comingSoon(context, l10n.wardrobeComingSoon),
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
                  onAction: () => _comingSoon(context, l10n.wardrobeComingSoon),
                )
              : _WardrobeGrid(
                  items: list,
                  onTap: () => _comingSoon(context, l10n.wardrobeComingSoon),
                ),
        ),
      ),
    );
  }
}

class _WardrobeGrid extends StatelessWidget {
  const _WardrobeGrid({required this.items, required this.onTap});

  final List<WardrobeItem> items;
  final VoidCallback onTap;

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
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return OutfitTile(
          imageUrl: item.displayImageUrl ?? '',
          label: item.title,
          onTap: onTap,
        );
      },
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
