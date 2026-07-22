import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../collections/local_collections.dart';
import '../studio/catalog_model_sheet.dart';
import '../tryon/open_tryon.dart';
import 'closet_category.dart';
import 'wardrobe_add_processing.dart';
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
  // The displayed item — seeded from the pushed copy and swapped in place when
  // the user categorizes/edits it (so the page reflects the edit without a pop).
  late WardrobeItem _item = widget.item;
  // Local wear state, seeded from the item and bumped optimistically on log
  // (the wear endpoint returns 204; we don't refetch this pushed item).
  late int _wearCount = widget.item.wearCount;
  late DateTime? _lastWorn = widget.item.lastWornAt;

  WardrobeItem get item => _item;

  Future<void> _editDetails() async {
    final updated = await context.push<WardrobeItem>(
      AppRoute.wardrobeCategorize,
      extra: _item,
    );
    if (updated != null && mounted) setState(() => _item = updated);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _tryOnMe() {
    if (!openTryOnWithItem(context, ref, item)) {
      _snack(AppLocalizations.of(context).tryOnStillPreparing);
    }
  }

  /// AI Enhance this piece (Pro/Pro Max, 4 credits) — non-blocking: starts the job
  /// and badges the item; the worker updates the cover on success / refunds on
  /// failure. Free users go to the paywall.
  Future<void> _enhance() async {
    final l10n = AppLocalizations.of(context);
    final credits = ref.read(creditsProvider).asData?.value;
    if (!(credits?.isSubscriber ?? false)) {
      context.push(AppRoute.paywall);
      return;
    }
    final cost = credits?.enhanceCost ?? 4;
    final ok = await showConfirmSheet(
      context,
      icon: Icons.auto_awesome,
      title: l10n.wardrobeEnhanceItem,
      message: l10n.aiCreditConfirm(cost),
      confirmLabel: l10n.wardrobeEnhanceItem,
      cancelLabel: l10n.commonCancel,
    );
    if (!ok || !mounted) return;
    // Run the enhance behind the same blocking progress sheet used for adds, then
    // pull the finished (enhanced) piece back in — no in-place "processing" state.
    final done = await showWardrobeEnhanceProcessing(context, ref, item: item);
    if (!done || !mounted) return;
    final items = ref.read(wardrobeItemsProvider).asData?.value;
    final fresh = items?.where((i) => i.id == item.id);
    if (fresh != null && fresh.isNotEmpty) {
      setState(() => _item = fresh.first);
    }
    _snack(l10n.addItemSaved);
  }

  /// Catalog Model Shot — put this piece on an AI fashion model (Pro/Pro Max).
  /// Free users go to the paywall.
  void _showOnModel() {
    final credits = ref.read(creditsProvider).asData?.value;
    if (!(credits?.isSubscriber ?? false)) {
      context.push(AppRoute.paywall);
      return;
    }
    showCatalogModelSheet(context, item);
  }

  Future<void> _markWorn() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(wardrobeRepositoryProvider).markWorn(item.id);
      if (mounted) {
        setState(() {
          _wearCount += 1;
          _lastWorn = DateTime.now();
        });
      }
      ref.invalidate(wardrobeItemsProvider);
      ref.invalidate(wardrobeViewProvider);
      ref.invalidate(wardrobeAnalyticsProvider);
      _snack(l10n.wardrobeWornLogged);
    } on ApiException {
      _snack(l10n.wardrobeActionError);
    }
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

    final displayName = closetItemName(item) ?? l10n.closetNeedsCategory;
    final needsCategory = (item.category ?? '').trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          IconButton(
            tooltip: l10n.categorizeEditDetails,
            onPressed: _busy ? null : _editDetails,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: isFav ? l10n.closetDetailUnfavorite : l10n.closetDetailFavorite,
            onPressed: () =>
                ref.read(closetFavoritesProvider.notifier).toggle(item.id),
            icon: Icon(
              isFav ? Icons.favorite : Icons.favorite_border,
              color: isFav ? AppColors.accent : null,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'enhance':
                  _enhance();
                case 'catalog':
                  _showOnModel();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'enhance',
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 18),
                    const SizedBox(width: AppSpace.sm),
                    Text(l10n.wardrobeEnhanceItem),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'catalog',
                child: Row(
                  children: [
                    const Icon(Icons.checkroom_rounded, size: 18),
                    const SizedBox(width: AppSpace.sm),
                    Text(l10n.closetShowOnModel),
                  ],
                ),
              ),
            ],
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
                Text(displayName, style: text.headlineSmall),
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
                if (needsCategory) ...[
                  const SizedBox(height: AppSpace.md),
                  _NeedsCategoryPrompt(onTap: _busy ? null : _editDetails),
                ],
                const SizedBox(height: AppSpace.md),
                _WearRow(
                  count: _wearCount,
                  lastWorn: _lastWorn,
                  onMarkWorn: _busy ? null : _markWorn,
                ),
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

/// Wear summary + "mark as worn" (CLAUDE.md §24, cost-per-wear). Wear data is
/// optional — the row renders fine for items that have never been worn.
class _WearRow extends StatelessWidget {
  const _WearRow({
    required this.count,
    required this.lastWorn,
    required this.onMarkWorn,
  });

  final int count;
  final DateTime? lastWorn;
  final VoidCallback? onMarkWorn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.checkroom_rounded, size: 18, color: AppColors.lavender),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.closetWornCount(count), style: text.bodyMedium),
                if (lastWorn != null)
                  Text(
                    l10n.closetLastWorn(DateFormat.yMMMd().format(lastWorn!)),
                    style: text.bodySmall?.copyWith(color: AppColors.graphite),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          TextButton.icon(
            onPressed: onMarkWorn,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l10n.wardrobeMarkWorn),
          ),
        ],
      ),
    );
  }
}

/// Friendly prompt shown when a piece has no category yet — turns the old
/// dead-end "Uncategorized" state into a clear call to action (spec).
class _NeedsCategoryPrompt extends StatelessWidget {
  const _NeedsCategoryPrompt({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  l10n.categorizePromptBody,
                  style: text.bodySmall?.copyWith(color: AppColors.accent),
                ),
              ),
              Text(
                l10n.categorizeAction,
                style: text.labelLarge?.copyWith(color: AppColors.accent),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.accent),
            ],
          ),
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
