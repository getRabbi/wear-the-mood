import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/outfit_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'outfit_providers.dart';

/// Builds a new outfit by multi-selecting owned wardrobe items (CLAUDE.md §5).
/// Reuses the closet grid; saving posts to `/v1/outfits` and the backend
/// re-checks ownership (§11). The cover defaults to the first selected piece.
class CreateOutfitScreen extends ConsumerStatefulWidget {
  const CreateOutfitScreen({super.key});

  @override
  ConsumerState<CreateOutfitScreen> createState() => _CreateOutfitScreenState();
}

class _CreateOutfitScreenState extends ConsumerState<CreateOutfitScreen> {
  final _nameController = TextEditingController();
  final List<String> _selected = []; // order = selection order
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _save(List<WardrobeItem> items) async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);

    // Cover = the first selected piece's image, until generated covers land.
    final cover = items
        .firstWhere((i) => i.id == _selected.first)
        .displayImageUrl;
    final name = _nameController.text.trim();

    try {
      await ref
          .read(outfitRepositoryProvider)
          .createOutfit(
            name: name.isEmpty ? null : name,
            itemIds: List.of(_selected),
            coverImageUrl: cover,
          );
      ref.invalidate(outfitsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.createOutfitSaved)));
      context.pop();
    } on ApiException {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.createOutfitError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wardrobe = ref.watch(wardrobeItemsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createOutfitTitle)),
      body: SafeArea(
        child: wardrobe.when(
          loading: () => const _ShimmerGrid(),
          error: (_, _) => ErrorState(
            title: l10n.wardrobeErrorTitle,
            onRetry: () => ref.invalidate(wardrobeItemsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (items) => items.isEmpty
              ? EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: l10n.wardrobeEmptyTitle,
                  message: l10n.createOutfitNoItemsMessage,
                )
              : _Builder(
                  items: items,
                  selected: _selected,
                  saving: _saving,
                  nameController: _nameController,
                  onToggle: _toggle,
                  onSave: () => _save(items),
                ),
        ),
      ),
    );
  }
}

class _Builder extends StatelessWidget {
  const _Builder({
    required this.items,
    required this.selected,
    required this.saving,
    required this.nameController,
    required this.onToggle,
    required this.onSave,
  });

  final List<WardrobeItem> items;
  final List<String> selected;
  final bool saving;
  final TextEditingController nameController;
  final void Function(String id) onToggle;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.lg,
                  AppSpace.lg,
                  AppSpace.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l10n.createOutfitNameLabel,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        l10n.createOutfitPickTitle,
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        l10n.createOutfitPickSubtitle,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpace.md,
                    crossAxisSpacing: AppSpace.md,
                    childAspectRatio: 0.66,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final item = items[i];
                    return _SelectableTile(
                      item: item,
                      selected: selected.contains(item.id),
                      onTap: () => onToggle(item.id),
                    );
                  }, childCount: items.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
            ],
          ),
        ),
        _BottomBar(
          child: PrimaryButton(
            label: l10n.createOutfitSave,
            icon: Icons.check_rounded,
            isLoading: saving,
            onPressed: selected.isEmpty ? null : onSave,
          ),
        ),
      ],
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final WardrobeItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.title,
      child: Stack(
        children: [
          OutfitTile(
            imageUrl: item.displayImageUrl ?? '',
            label: item.title,
            onTap: onTap,
          ),
          if (selected)
            const Positioned(
              top: AppSpace.sm,
              right: AppSpace.sm,
              child: _CheckBadge(),
            ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: child,
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
