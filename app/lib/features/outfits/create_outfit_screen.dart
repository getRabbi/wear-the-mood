import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/outfit_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import '../shell/shell_providers.dart';
import '../tryon/tryon_preselect.dart';
import '../wardrobe/wardrobe_providers.dart';
import 'outfit_providers.dart';
import 'outfit_slots.dart';

/// Builds (or edits) a full outfit *set* from owned closet pieces — top + bottom
/// + shoes + bag + eyewear + jewelry … (real-device polish; the old flow was a
/// flat multi-select). Each slot holds one piece; pieces that don't map to a slot
/// are preserved as "extras" so editing never drops anything. Saving posts to
/// `/v1/outfits` (create) or PUT (edit); the backend re-checks ownership (§11).
class CreateOutfitScreen extends ConsumerStatefulWidget {
  const CreateOutfitScreen({super.key, this.existing});

  /// When set, the builder opens in edit mode pre-filled with this outfit.
  final Outfit? existing;

  @override
  ConsumerState<CreateOutfitScreen> createState() => _CreateOutfitScreenState();
}

class _CreateOutfitScreenState extends ConsumerState<CreateOutfitScreen> {
  final _nameController = TextEditingController();
  // slot → chosen item id; plus extras (valid pieces with no matching slot).
  final Map<OutfitSlot, String> _slotIds = {};
  final List<String> _extraIds = [];
  bool _seeded = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.existing?.name ?? '';
    final items = ref.read(wardrobeItemsProvider).asData?.value;
    if (items != null) _seed(items);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Map an edited outfit's saved pieces onto slots once the closet is loaded.
  void _seed(List<WardrobeItem> items) {
    if (_seeded) return;
    final existing = widget.existing;
    if (existing == null) {
      _seeded = true;
      return;
    }
    final byId = {for (final i in items) i.id: i};
    for (final id in existing.itemIds) {
      final item = byId[id];
      if (item == null) continue; // no longer owned → backend would reject it
      final slot = slotForItem(item);
      if (slot != null && !_slotIds.containsKey(slot)) {
        _slotIds[slot] = id;
      } else {
        _extraIds.add(id);
      }
    }
    _seeded = true;
  }

  /// Ordered selected ids: filled slots in slot order, then extras.
  List<String> get _selectedIds => [
    for (final slot in OutfitSlot.values) ?_slotIds[slot],
    ..._extraIds,
  ];

  List<WardrobeItem> _selectedItems(List<WardrobeItem> closet) {
    final byId = {for (final i in closet) i.id: i};
    return [
      for (final id in _selectedIds) ?byId[id],
    ];
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickForSlot(OutfitSlot slot, List<WardrobeItem> closet) async {
    final picked = await showModalBottomSheet<WardrobeItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _ItemPickerSheet(
        slot: slot,
        closet: closet,
        selectedId: _slotIds[slot],
      ),
    );
    if (picked != null) {
      setState(() {
        // If the piece sat in extras or another slot, move it here cleanly.
        _extraIds.remove(picked.id);
        _slotIds.removeWhere((s, id) => id == picked.id);
        _slotIds[slot] = picked.id;
      });
    }
  }

  Future<void> _tryOnFullLook(List<WardrobeItem> closet) async {
    final items = _selectedItems(closet);
    if (items.isEmpty) return;
    ref.read(tryOnPreselectProvider.notifier).setItems(items);
    ref.read(shellTabProvider.notifier).select(ShellTabs.tryOn);
    if (mounted) context.pop();
  }

  Future<void> _save(List<WardrobeItem> closet) async {
    final ids = _selectedIds;
    if (ids.isEmpty || _saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);

    final items = _selectedItems(closet);
    final cover = items.isEmpty ? null : items.first.displayImageUrl;
    final name = _nameController.text.trim();
    final repo = ref.read(outfitRepositoryProvider);

    try {
      if (_isEdit) {
        await repo.updateOutfit(
          widget.existing!.id,
          name: name.isEmpty ? null : name,
          itemIds: ids,
          coverImageUrl: cover,
        );
      } else {
        await repo.createOutfit(
          name: name.isEmpty ? null : name,
          itemIds: ids,
          coverImageUrl: cover,
        );
      }
      ref.invalidate(outfitsProvider);
      if (!mounted) return;
      _snack(_isEdit ? l10n.outfitUpdated : l10n.createOutfitSaved);
      context.pop();
    } on ApiException {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(l10n.createOutfitError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final wardrobe = ref.watch(wardrobeItemsProvider);
    // Seed once the closet arrives (edit mode opened before the list loaded).
    ref.listen(wardrobeItemsProvider, (_, next) {
      final items = next.asData?.value;
      if (items != null && !_seeded) setState(() => _seed(items));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.outfitEditTitle : l10n.createOutfitTitle),
      ),
      body: SafeArea(
        child: wardrobe.when(
          loading: () => SkeletonLoader.grid(aspectRatio: 0.66),
          error: (_, _) => ErrorState(
            title: l10n.wardrobeErrorTitle,
            onRetry: () => ref.invalidate(wardrobeItemsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (closet) => closet.isEmpty
              ? EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: l10n.wardrobeEmptyTitle,
                  message: l10n.createOutfitNoItemsMessage,
                )
              : _Builder(
                  closet: closet,
                  slotIds: _slotIds,
                  extraIds: _extraIds,
                  nameController: _nameController,
                  saving: _saving,
                  selectedCount: _selectedIds.length,
                  onPickSlot: (slot) => _pickForSlot(slot, closet),
                  onClearSlot: (slot) =>
                      setState(() => _slotIds.remove(slot)),
                  onRemoveExtra: (id) => setState(() => _extraIds.remove(id)),
                  onTryOn: () => _tryOnFullLook(closet),
                  onSave: () => _save(closet),
                ),
        ),
      ),
    );
  }
}

class _Builder extends StatelessWidget {
  const _Builder({
    required this.closet,
    required this.slotIds,
    required this.extraIds,
    required this.nameController,
    required this.saving,
    required this.selectedCount,
    required this.onPickSlot,
    required this.onClearSlot,
    required this.onRemoveExtra,
    required this.onTryOn,
    required this.onSave,
  });

  final List<WardrobeItem> closet;
  final Map<OutfitSlot, String> slotIds;
  final List<String> extraIds;
  final TextEditingController nameController;
  final bool saving;
  final int selectedCount;
  final void Function(OutfitSlot slot) onPickSlot;
  final void Function(OutfitSlot slot) onClearSlot;
  final void Function(String id) onRemoveExtra;
  final VoidCallback onTryOn;
  final VoidCallback onSave;

  WardrobeItem? _byId(String? id) {
    if (id == null) return null;
    for (final i in closet) {
      if (i.id == id) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final extras = [for (final id in extraIds) _byId(id)].whereType<WardrobeItem>();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
            ),
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
              Text(l10n.outfitBuilderPickTitle, style: text.headlineSmall),
              const SizedBox(height: AppSpace.xs),
              Text(l10n.outfitBuilderPickSubtitle, style: text.bodySmall),
              const SizedBox(height: AppSpace.md),
              for (final slot in OutfitSlot.values) ...[
                _SlotCard(
                  slot: slot,
                  item: _byId(slotIds[slot]),
                  onPick: () => onPickSlot(slot),
                  onClear: () => onClearSlot(slot),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              if (extras.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(l10n.outfitBuilderOtherPieces, style: text.titleMedium),
                const SizedBox(height: AppSpace.sm),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final item in extras)
                      InputChip(
                        avatar: const Icon(Icons.checkroom_rounded, size: 16),
                        label: Text(
                          item.title ?? l10n.closetNeedsCategory,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () => onRemoveExtra(item.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _BottomBar(
          child: Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: l10n.outfitTryFullLook,
                  icon: Icons.auto_awesome,
                  onPressed: selectedCount == 0 ? null : onTryOn,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: PrimaryButton(
                  label: l10n.createOutfitSave,
                  icon: Icons.check_rounded,
                  isLoading: saving,
                  onPressed: selectedCount == 0 ? null : onSave,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One outfit slot: empty (an "Add" affordance) or filled (thumbnail + name +
/// replace/remove).
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.item,
    required this.onPick,
    required this.onClear,
  });

  final OutfitSlot slot;
  final WardrobeItem? item;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final filled = item != null;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: filled ? AppColors.accent : AppColors.glassBorder,
              width: filled ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: filled
                    ? SmartImageCard(
                        imageUrl: item!.displayImageUrl ?? '',
                        aspectRatio: 1,
                        fit: BoxFit.contain,
                        padded: true,
                      )
                    // Empty slot: the curated slot cover when available, else
                    // the original icon chip — so empty slots read as
                    // intentional, not unfinished (CATEGORY_COVER_IMAGES.md).
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: CoverImage(
                          coverKey: slot.coverKey,
                          fit: BoxFit.cover,
                          fallback: (_) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.glassFill,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Icon(slot.icon, color: AppColors.lavender),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.label(l10n), style: text.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      filled
                          ? (item!.title ?? l10n.closetNeedsCategory)
                          : l10n.outfitSlotAdd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: filled ? null : AppColors.graphite,
                      ),
                    ),
                  ],
                ),
              ),
              if (filled)
                IconButton(
                  tooltip: l10n.outfitSlotRemove,
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                )
              else
                const Icon(Icons.add_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
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

/// Mid-height closet picker for a slot — slot-matching pieces first, but all
/// pieces are selectable (the user knows best). Returns the chosen item.
class _ItemPickerSheet extends StatefulWidget {
  const _ItemPickerSheet({
    required this.slot,
    required this.closet,
    required this.selectedId,
  });

  final OutfitSlot slot;
  final List<WardrobeItem> closet;
  final String? selectedId;

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  bool _onlyMatching = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final matching = widget.closet.where(widget.slot.matches).toList();
    final showMatchToggle = matching.isNotEmpty && matching.length != widget.closet.length;
    final items = (_onlyMatching && matching.isNotEmpty)
        ? matching
        : widget.closet;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.xs,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: Row(
                children: [
                  Icon(widget.slot.icon, color: AppColors.lavender, size: 20),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      l10n.outfitPickForSlot(widget.slot.label(l10n)),
                      style: text.titleMedium,
                    ),
                  ),
                  if (showMatchToggle)
                    TextButton(
                      onPressed: () =>
                          setState(() => _onlyMatching = !_onlyMatching),
                      child: Text(
                        _onlyMatching ? l10n.outfitShowAll : l10n.outfitShowMatching,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  0,
                  AppSpace.lg,
                  AppSpace.lg,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: AppSpace.md,
                  crossAxisSpacing: AppSpace.md,
                  childAspectRatio: 0.74,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final selected = item.id == widget.selectedId;
                  return Stack(
                    children: [
                      SmartImageCard(
                        imageUrl: item.displayImageUrl ?? '',
                        aspectRatio: 1,
                        fit: BoxFit.contain,
                        padded: true,
                        onTap: () => Navigator.of(context).pop(item),
                      ),
                      if (selected)
                        const Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: AppColors.accent,
                            child: Icon(Icons.check_rounded,
                                size: 14, color: Colors.white),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
