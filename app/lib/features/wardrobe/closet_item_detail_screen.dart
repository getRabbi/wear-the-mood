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
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import 'wardrobe_providers.dart';

/// Closet item detail (redesign spec): a large image, the piece's name/category,
/// the key actions (Try on me, Style it, Favorite, Delete) and AI styling
/// suggestions, plus more pieces from the closet. Reuses existing wardrobe logic
/// — nothing new server-side.
class ClosetItemDetailScreen extends ConsumerStatefulWidget {
  const ClosetItemDetailScreen({super.key, required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<ClosetItemDetailScreen> createState() =>
      _ClosetItemDetailScreenState();
}

class _ClosetItemDetailScreenState
    extends ConsumerState<ClosetItemDetailScreen> {
  bool _busy = false;

  WardrobeItem get item => widget.item;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _tryOnMe() {
    ref.read(tryOnPreselectProvider.notifier).setItem(item);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
    context.pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showConfirmSheet(
      context,
      icon: Icons.delete_outline_rounded,
      title: l10n.wardrobeDeleteTitle,
      message: l10n.wardrobeDeleteBody,
      confirmLabel: l10n.wardrobeDeleteConfirm,
      cancelLabel: l10n.wardrobeDeleteCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardrobeRepositoryProvider).deleteItem(item.id);
      ref.invalidate(wardrobeItemsProvider);
      ref.invalidate(wardrobeViewProvider);
      if (mounted) {
        _snack(l10n.wardrobeDeleted);
        context.pop();
      }
    } on ApiException {
      if (mounted) {
        setState(() => _busy = false);
        _snack(l10n.wardrobeDeleteError);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final isFav = ref.watch(closetFavoritesProvider).contains(item.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title ?? l10n.closetUncategorized),
        actions: [
          IconButton(
            tooltip: isFav ? l10n.closetDetailUnfavorite : l10n.closetDetailFavorite,
            onPressed: () =>
                ref.read(closetFavoritesProvider.notifier).toggle(item.id),
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? AppColors.accent : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.xl,
              ),
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: SmartImageCard(
                    imageUrl: item.displayImageUrl ?? '',
                    aspectRatio: 1,
                    fit: BoxFit.contain,
                    padded: true,
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(item.title ?? l10n.closetUncategorized, style: text.headlineSmall),
                if ((item.category ?? '').isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Row(
                    children: [
                      const Icon(Icons.sell_outlined, size: 16, color: AppColors.violet),
                      const SizedBox(width: 6),
                      Text(
                        item.category!,
                        style: text.bodyMedium?.copyWith(color: AppColors.violet),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpace.lg),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: l10n.closetDetailTryOnMe,
                        icon: Icons.auto_awesome,
                        onPressed: _tryOnMe,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: SecondaryButton(
                        label: l10n.closetStyleIt,
                        icon: Icons.style_outlined,
                        onPressed: () => context.push(AppRoute.outfitsCreate),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                _AiStyling(),
                const SizedBox(height: AppSpace.xl),
                _RelatedItems(currentId: item.id),
                const SizedBox(height: AppSpace.lg),
                TextButton.icon(
                  onPressed: _busy ? null : _delete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.wardrobeRemove),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiStyling extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return PremiumDarkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              const SizedBox(width: AppSpace.sm),
              Text(
                l10n.closetDetailPairsTitle,
                style: text.titleMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            l10n.closetDetailPairsValue,
            style: text.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            l10n.closetDetailBestForTitle,
            style: text.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            l10n.closetDetailBestForValue,
            style: text.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _RelatedItems extends ConsumerWidget {
  const _RelatedItems({required this.currentId});

  final String currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final related = items.where((i) => i.id != currentId).take(8).toList();
    if (related.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.closetDetailRelated, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: related.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) {
              final it = related[i];
              return SizedBox(
                width: 110,
                child: SmartImageCard(
                  imageUrl: it.displayImageUrl ?? '',
                  aspectRatio: 1,
                  fit: BoxFit.contain,
                  padded: true,
                  onTap: () => context.push(AppRoute.wardrobeItem, extra: it),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
