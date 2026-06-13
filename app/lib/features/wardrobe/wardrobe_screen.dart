import 'dart:ui' show ImageFilter;

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

  /// Long-press menu for a piece: log a wear or remove it (§24).
  Future<void> _itemActions(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
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
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text(l10n.wardrobeMarkWorn),
              onTap: () => Navigator.of(ctx).pop('wear'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              title: Text(l10n.wardrobeRemove),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'wear') {
      await _markWorn(context, ref, item);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref, item);
    }
  }

  Future<void> _markWorn(
    BuildContext context,
    WidgetRef ref,
    WardrobeItem item,
  ) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(wardrobeRepositoryProvider).markWorn(item.id);
      ref.invalidate(wardrobeAnalyticsProvider);
      if (context.mounted) _snack(context, l10n.wardrobeWornLogged);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.wardrobeActionError);
    }
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
      ref.invalidate(wardrobeViewProvider);
      if (context.mounted) _snack(context, l10n.wardrobeDeleted);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.wardrobeDeleteError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(wardrobeViewProvider);
    final searching = ref.watch(wardrobeSearchQueryProvider).trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navWardrobe),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoute.wardrobeInsights),
            icon: const Icon(Icons.insights_outlined),
            tooltip: l10n.insightsTitle,
          ),
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
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: _SearchField(),
            ),
            Expanded(
              child: view.when(
                loading: () => const _ShimmerGrid(),
                error: (_, _) => ErrorState(
                  title: l10n.wardrobeErrorTitle,
                  onRetry: () => ref.invalidate(wardrobeViewProvider),
                  retryLabel: l10n.commonRetry,
                ),
                data: (list) => list.isEmpty
                    ? (searching
                          ? EmptyState(
                              icon: Icons.search_off_rounded,
                              title: l10n.wardrobeSearchEmptyTitle,
                              message: l10n.wardrobeSearchEmptyMessage,
                            )
                          : EmptyState(
                              icon: Icons.checkroom_outlined,
                              title: l10n.wardrobeEmptyTitle,
                              message: l10n.wardrobeEmptyMessage,
                              actionLabel: l10n.wardrobeAdd,
                              onAction: () =>
                                  context.push(AppRoute.wardrobeAdd),
                            ))
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(wardrobeItemsProvider);
                          ref.invalidate(wardrobeViewProvider);
                        },
                        child: _WardrobeGrid(
                          items: list,
                          onLongPress: (item) =>
                              _itemActions(context, ref, item),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Closet search box (§2.1). Searches on submit (not per keystroke) to keep the
/// query-embedding cost down; the clear button resets to browsing the closet.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(wardrobeSearchQueryProvider),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    ref.read(wardrobeSearchQueryProvider.notifier).setQuery(value);
  }

  void _clear() {
    _controller.clear();
    ref.read(wardrobeSearchQueryProvider.notifier).setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onSubmitted: _submit,
      decoration: InputDecoration(
        hintText: l10n.wardrobeSearchHint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _clear,
                tooltip: l10n.commonClear,
              ),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
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
            const Positioned.fill(child: _ProcessingOverlay()),
          ],
        );
      },
    );
  }
}

/// Covers a tile while its background-removal cutout is still generating (§2.2).
/// A clear, modern overlay — frosted scrim + spinner + "Removing background" —
/// so the user understands what's happening instead of seeing a vague badge.
class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.ink.withValues(alpha: 0.35),
                AppColors.ink.withValues(alpha: 0.66),
              ],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    l10n.wardrobeRemovingBackground,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    l10n.wardrobeProcessingHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
