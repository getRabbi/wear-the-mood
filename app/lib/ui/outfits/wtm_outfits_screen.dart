import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/outfit_repository.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_outfit_composer.dart';

/// Resolve owned pieces by id — the outfit model stores item ids, the UI needs
/// the pieces (image + label). Missing ids (deleted pieces) are skipped.
Map<String, WardrobeItem> wardrobeById(List<WardrobeItem> items) =>
    {for (final i in items) i.id: i};

/// WTM Outfit Maker (board §3.19, P5) — the saved-outfits grid on
/// [outfitsProvider] followed by the composer. Saving creates/updates via the
/// existing outfit backend; a saved outfit's "Try It On" seeds MoodMirror
/// Step 2 (from the detail screen).
class WtmOutfitsScreen extends ConsumerWidget {
  const WtmOutfitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final outfitsAsync = ref.watch(outfitsProvider);
    final byId = wardrobeById(
      ref.watch(wardrobeItemsProvider).asData?.value ?? const [],
    );

    return WtmPage(
      title: l10n.wtmOutfitsTitle,
      eyebrow: l10n.wtmOutfitsEyebrow,
      children: [
        EyebrowLabel(l10n.wtmOutfitsSaved),
        const SizedBox(height: WtmSpace.s10),
        ...outfitsAsync.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: () => [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 9,
              crossAxisSpacing: 9,
              childAspectRatio: 1.4,
              children: [
                for (var i = 0; i < 4; i++)
                  const LoadingShimmer(
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius:
                        BorderRadius.all(Radius.circular(WtmRadius.card)),
                  ),
              ],
            ),
          ],
          error: (_, _) => [
            WtmErrorState(
              title: l10n.wtmOutfitsErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(outfitsProvider),
            ),
          ],
          data: (outfits) => outfits.isEmpty
              ? [
                  Text(l10n.wtmOutfitsEmptyMessage, style: WtmType.micro),
                ]
              : [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 1.4,
                    children: [
                      for (final outfit in outfits)
                        _SavedOutfitCard(outfit: outfit, byId: byId),
                    ],
                  ),
                ],
        ),
        const SizedBox(height: WtmSpace.s18),
        EyebrowLabel(l10n.wtmOutfitsComposer),
        const SizedBox(height: WtmSpace.s10),
        const WtmOutfitComposerCard(),
      ],
    );
  }
}

class _SavedOutfitCard extends StatelessWidget {
  const _SavedOutfitCard({required this.outfit, required this.byId});

  final Outfit outfit;
  final Map<String, WardrobeItem> byId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pieces = [
      for (final id in outfit.itemIds.take(3))
        if (byId[id] != null) byId[id]!,
    ];
    final name = (outfit.name ?? '').trim();
    return Semantics(
      button: true,
      label: name.isEmpty ? l10n.wtmOutfitsUntitled : name,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () =>
              context.push(AppRoute.wtmOutfitDetail, extra: outfit),
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s10),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      for (var t = 0; t < 3; t++) ...[
                        if (t > 0) const SizedBox(width: 5),
                        Expanded(
                          child: t < pieces.length
                              ? FabricTile(
                                  imageUrl: pieces[t].displayImageUrl,
                                  swatchIndex: t,
                                  aspectRatio: null,
                                  fit: BoxFit.contain,
                                  radius: 9,
                                )
                              : FabricTile(
                                  swatchIndex: t + 3,
                                  aspectRatio: null,
                                  radius: 9,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: WtmSpace.s8),
                Text(
                  name.isEmpty ? l10n.wtmOutfitsUntitled : name,
                  style: WtmType.labelMedium.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.wtmOutfitPieces(outfit.itemCount),
                  style: WtmType.micro,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The composer (board §3.19): 4 positional slots + a closet picker strip + a
/// serif name field + Save/Update. Binds to [wtmOutfitComposerProvider] so the
/// detail's "Edit" can pre-fill it.
class WtmOutfitComposerCard extends ConsumerStatefulWidget {
  const WtmOutfitComposerCard({super.key});

  @override
  ConsumerState<WtmOutfitComposerCard> createState() =>
      _WtmOutfitComposerCardState();
}

class _WtmOutfitComposerCardState extends ConsumerState<WtmOutfitComposerCard> {
  static const _slotKeys = ['top', 'bottom', 'layer', 'extra'];
  int _activeSlot = 0;
  bool _busy = false;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: ref.read(wtmOutfitComposerProvider).name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _slotLabel(AppLocalizations l10n, int i) => switch (_slotKeys[i]) {
        'top' => l10n.wtmOutfitSlotTop,
        'bottom' => l10n.wtmOutfitSlotBottom,
        'layer' => l10n.wtmOutfitSlotLayer,
        _ => l10n.wtmOutfitSlotExtra,
      };

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final draft = ref.read(wtmOutfitComposerProvider);
    if (draft.itemIds.isEmpty) {
      wtmSnack(context, l10n.wtmOutfitsPickFirst);
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(outfitRepositoryProvider);
      final name = draft.name.trim().isEmpty ? null : draft.name.trim();
      if (draft.isEditing) {
        await repo.updateOutfit(draft.editingId!,
            name: name, itemIds: draft.itemIds);
      } else {
        await repo.createOutfit(name: name, itemIds: draft.itemIds);
      }
      ref.invalidate(outfitsProvider);
      ref.read(wtmOutfitComposerProvider.notifier).reset();
      _nameCtrl.clear();
      if (mounted) {
        setState(() => _activeSlot = 0);
        wtmSnack(context, l10n.wtmOutfitsSavedSnack);
      }
    } catch (_) {
      if (mounted) wtmSnack(context, l10n.wtmOutfitsSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(wtmOutfitComposerProvider);
    final byId = wardrobeById(
      ref.watch(wardrobeItemsProvider).asData?.value ?? const [],
    );

    // Re-sync the name field when Edit loads a different outfit (or a reset
    // flips editing off) — the field is otherwise user-driven.
    ref.listen(wtmOutfitComposerProvider.select((s) => s.editingId), (_, _) {
      _nameCtrl.text = ref.read(wtmOutfitComposerProvider).name;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 1.6,
          children: [
            for (var i = 0; i < WtmComposerState.slotCount; i++)
              _Slot(
                label: _slotLabel(l10n, i),
                active: _activeSlot == i,
                item: draft.slots[i] == null ? null : byId[draft.slots[i]],
                filled: draft.slots[i] != null,
                onTap: () {
                  final isFilledActive =
                      draft.slots[i] != null && _activeSlot == i;
                  if (isFilledActive) {
                    ref
                        .read(wtmOutfitComposerProvider.notifier)
                        .clearSlot(i);
                  }
                  setState(() => _activeSlot = i);
                },
              ),
          ],
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(l10n.wtmOutfitsComposerHint, style: WtmType.micro),
        const SizedBox(height: WtmSpace.s10),
        _PickerStrip(
          byId: byId,
          activeSlot: _activeSlot,
        ),
        const SizedBox(height: WtmSpace.s14),
        TextField(
          controller: _nameCtrl,
          style: WtmType.h2.copyWith(fontSize: 18),
          cursorColor: WtmColors.gold,
          onChanged: ref.read(wtmOutfitComposerProvider.notifier).setName,
          decoration: InputDecoration(
            hintText: l10n.wtmOutfitsNameHint,
            hintStyle:
                WtmType.h2.copyWith(fontSize: 18, color: WtmColors.faint),
            filled: true,
            fillColor: WtmColors.iconBtnBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(WtmRadius.button),
              borderSide: const BorderSide(color: WtmColors.chipOnBorder),
            ),
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        GradientCta(
          label: draft.isEditing
              ? l10n.wtmOutfitsUpdate
              : l10n.wtmOutfitsSave,
          icon: const WtmIcon(WtmGlyph.check, size: 15, color: WtmColors.ctaText),
          onPressed: _busy ? null : _save,
        ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.label,
    required this.active,
    required this.item,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool active;
  final WardrobeItem? item;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: WtmDashedBox(
            child: Container(
              decoration: BoxDecoration(
                color: active ? WtmColors.chipOnBg : WtmColors.iconBtnBg,
                borderRadius: BorderRadius.circular(WtmRadius.tile),
              ),
              child: filled
                  ? Padding(
                      padding: const EdgeInsets.all(6),
                      child: FabricTile(
                        imageUrl: item?.displayImageUrl,
                        swatchIndex: 0,
                        aspectRatio: null,
                        fit: BoxFit.contain,
                        radius: 9,
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WtmIcon(
                            WtmGlyph.plus,
                            size: 15,
                            color: active ? WtmColors.gold : WtmColors.faint,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label.toUpperCase(),
                            style: WtmType.micro.copyWith(
                              fontSize: 8.5,
                              letterSpacing: 1.02,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal closet strip — tap a piece to drop it into the active slot.
/// Empty closet routes to Add Garment instead of showing a dead strip.
class _PickerStrip extends ConsumerWidget {
  const _PickerStrip({required this.byId, required this.activeSlot});

  final Map<String, WardrobeItem> byId;
  final int activeSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = byId.values.toList();
    if (items.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(l10n.wtmOutfitsNoCloset, style: WtmType.micro),
          ),
          GoldPill(
            label: l10n.wtmStylistEmptyCta,
            onTap: () => context.push(AppRoute.wtmClosetAdd),
          ),
        ],
      );
    }
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final item = items[i];
          return SizedBox(
            width: 64,
            child: FabricTile(
              imageUrl: item.displayImageUrl,
              swatchIndex: i,
              aspectRatio: null,
              fit: BoxFit.contain,
              radius: 9,
              semanticLabel: item.title,
              onTap: () => ref
                  .read(wtmOutfitComposerProvider.notifier)
                  .setSlot(activeSlot, item.id),
            ),
          );
        },
      ),
    );
  }
}
