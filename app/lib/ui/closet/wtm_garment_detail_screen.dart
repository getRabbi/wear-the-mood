import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';
import '../../core/router/routes.dart';
import '../../data/models/credits.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../features/tryon/tryon_preselect.dart';
import '../../features/wardrobe/closet_category.dart';
import '../../features/wardrobe/garment_category.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import '../../theme/wtm_typography.dart';
import '../community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../widgets/widgets.dart';
import 'wtm_cutout_gate.dart';
import 'wtm_category_picker.dart';
import 'wtm_category_resolver.dart';
import 'wtm_enhance.dart';

/// Garment detail (§3.9, P3) — hero cutout on a fabric swatch, category/tag
/// chips, wear stats, and the real actions: heart → local Favorites (§3.1),
/// Try It On → MoodMirror, Edit → name/category sheet (PATCH), Delete →
/// confirm + DELETE. Data arrives via the route extra; edits update in place.
class WtmGarmentDetailScreen extends ConsumerStatefulWidget {
  const WtmGarmentDetailScreen({super.key, required this.item});

  final WardrobeItem item;

  @override
  ConsumerState<WtmGarmentDetailScreen> createState() =>
      _WtmGarmentDetailScreenState();
}

class _WtmGarmentDetailScreenState
    extends ConsumerState<WtmGarmentDetailScreen> {
  late WardrobeItem _item = widget.item;
  bool _busy = false;
  bool _deleting =
      false; // drives the "Deleting…" button feedback (mobile QA #3)

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final favorites = ref.watch(closetFavoritesProvider);
    final favorite = favorites.contains(_item.id);
    final name = closetItemName(_item) ?? l10n.wtmGarmentUntitled;

    return WtmPage(
      title: name,
      eyebrow: l10n.wtmClosetTitle,
      children: [
        Stack(
          children: [
            FabricTile(
              imageUrl: _item.displayImageUrl,
              isCutout: _item.displaysCutout,
              swatchIndex: _item.id.hashCode.abs() % 8,
              fit: BoxFit.contain,
              semanticLabel: name,
            ),
            Positioned(
              top: WtmSpace.s10,
              right: WtmSpace.s10,
              child: Semantics(
                button: true,
                label: favorite
                    ? l10n.wtmGarmentFavoriteRemove
                    : l10n.wtmGarmentFavoriteAdd,
                child: ExcludeSemantics(
                  child: PressableScale(
                    child: GestureDetector(
                      onTap: () => ref
                          .read(closetFavoritesProvider.notifier)
                          .toggle(_item.id),
                      // Over the garment figure, whose tile is deliberately
                      // LIGHT so cutouts read — the old 35% scrim let the
                      // glyph sink into a pale shirt.
                      child: AnimatedContainer(
                        duration: WtmMotion.fast,
                        curve: WtmMotion.easing,
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: favorite
                              ? WtmGlass.selectedFill
                              : WtmGlass.overlayFill,
                          border: Border.all(
                            color: favorite
                                ? WtmGlass.selectedBorder
                                : WtmGlass.overlayBorder,
                          ),
                          boxShadow: WtmGlass.overlayShadow,
                        ),
                        alignment: Alignment.center,
                        child: WtmIcon(
                          WtmGlyph.heart,
                          size: 15,
                          color: favorite
                              ? WtmColors.gold
                              : WtmGlass.overlayForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: WtmSpace.s14),
        Wrap(
          spacing: WtmSpace.s6,
          runSpacing: WtmSpace.s6,
          children: [
            // The category, as a chip that is also the way to change it. A
            // piece whose category we cannot read says so and opens the same
            // editor — the one action that fixes it is the one it offers.
            WtmChip(
              label:
                  garmentCategoryOf(_item.category)?.label(l10n) ??
                  ((_item.category?.trim().isNotEmpty ?? false)
                      ? _item.category!.trim()
                      : l10n.closetNeedsCategory),
              on: garmentCategoryOf(_item.category) != null,
              onTap: _busy ? null : () => _edit(l10n),
            ),
            if (_item.color?.trim().isNotEmpty ?? false)
              WtmChip(label: _item.color!.trim()),
            for (final tag in _item.tags.take(6)) WtmChip(label: tag),
          ],
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          _item.wearCount > 0
              ? l10n.wtmGarmentWearStats(
                  _item.wearCount,
                  _item.lastWornAt == null
                      ? '—'
                      : DateFormat.MMMd().format(_item.lastWornAt!),
                )
              : l10n.wtmGarmentNeverWorn,
          style: WtmType.micro,
        ),
        const SizedBox(height: WtmSpace.s16),
        GradientCta(
          label: l10n.wtmGarmentTryOn,
          icon: const WtmIcon(
            WtmGlyph.sparkle,
            size: 15,
            color: WtmColors.ctaText,
          ),
          onPressed: _busy
              ? null
              : () async {
                  // A piece the server cannot identify is asked about first,
                  // right here, with the garment on screen — and the handoff
                  // then continues on its own. Backing out seeds nothing and
                  // charges nothing.
                  final ready = await wtmEnsureCategory(context, _item);
                  if (ready == null || !context.mounted) return;
                  setState(() => _item = ready);
                  // Queue this piece so Step 2 opens pre-filled (§8 handoff).
                  ref.read(tryOnPreselectProvider.notifier).setItem(ready);
                  context.push(AppRoute.wtmMirror);
                },
        ),
        const SizedBox(height: WtmSpace.s10),
        // AI Enhance any background-removed piece later (mobile QA #6):
        // Pro/Pro Max runs the real enhance job; free users land on the
        // paywall (never a broken button). Hidden once enhanced.
        if (!_item.aiEnhanced) ...[
          GhostButton(
            label: _item.isEnhancing
                ? l10n.wtmEnhanceProgress
                : l10n.wardrobeEnhanceItem,
            icon: const WtmIcon(
              WtmGlyph.sparkle,
              size: 15,
              color: WtmColors.gold,
            ),
            foregroundColor: WtmColors.gold,
            borderColor: WtmColors.pillBorder,
            onPressed: _busy || _item.isEnhancing ? null : _enhance,
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        // Free AUTOMATIC re-run of the cutout (gated). Separate feature and
        // separate gate from the manual editor below — see [canImproveCutout].
        // Hidden while an attempt is in flight rather than shown disabled, so the
        // user is never invited into a tap the server has to reject.
        if (canImproveCutout(
          _item,
          enabled: ref.watch(improveCutoutEnabledProvider),
        )) ...[
          GhostButton(
            label: l10n.wardrobeImproveEdges,
            icon: const WtmIcon(
              WtmGlyph.sparkle,
              size: 15,
              color: WtmColors.text,
            ),
            onPressed: _busy ? null : () => _improveEdges(l10n),
          ),
          const SizedBox(height: WtmSpace.s10),
        ] else if (_item.isProcessingCutout &&
            ref.watch(improveCutoutEnabledProvider) &&
            _item.cutoutUrl != null) ...[
          // An improvement is running: say so, and keep it un-tappable.
          GhostButton(
            label: l10n.wardrobeImproveEdgesQueued,
            icon: const WtmIcon(
              WtmGlyph.sparkle,
              size: 15,
              color: WtmColors.faint,
            ),
            onPressed: null,
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        // Free manual cutout correction (gated). Shown only for a piece that has
        // a background-removed cutout to fix; never a dead button when disabled.
        // Same rule on every platform — see [canFixCutout].
        if (canFixCutout(
          _item,
          enabled: ref.watch(cutoutEditorEnabledProvider),
        )) ...[
          GhostButton(
            label: l10n.wardrobeFixCutout,
            icon: const WtmIcon(
              WtmGlyph.erase,
              size: 15,
              color: WtmColors.text,
            ),
            onPressed: _busy ? null : _fixCutout,
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        // Share Look → Create Post prefilled with this piece's image.
        GhostButton(
          label: l10n.wtmShareLook,
          icon: const WtmIcon(WtmGlyph.users, size: 15, color: WtmColors.text),
          onPressed: _busy || _item.displayImageUrl == null
              ? null
              : () => context.push(
                  AppRoute.wtmCompose,
                  extra: WtmComposeArgs(imageUrl: _item.displayImageUrl),
                ),
        ),
        const SizedBox(height: WtmSpace.s10),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: l10n.wtmGarmentEdit,
                onPressed: _busy ? null : () => _edit(l10n),
              ),
            ),
            const SizedBox(width: WtmSpace.s10),
            Expanded(
              child: GhostButton(
                label: _deleting
                    ? l10n.wtmGarmentDeleting
                    : l10n.wtmGarmentDelete,
                icon: _deleting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: WtmColors.danger,
                        ),
                      )
                    : null,
                foregroundColor: WtmColors.danger,
                onPressed: _busy ? null : () => _delete(l10n),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Pro/Pro Max: confirm the credit spend, run the enhance job behind the
  /// WTM progress dialog, and show the upgraded cover. Free → paywall (§18).
  Future<void> _enhance() async {
    final l10n = AppLocalizations.of(context);
    // AWAIT the real plan — creditsProvider is autoDispose, so a bare read
    // here returns loading/null and mis-routed even Pro Max to the paywall
    // (mobile QA #3). A fetch failure is an error, never a paywall.
    setState(() => _busy = true);
    final Credits credits;
    try {
      credits = await ref.read(creditsProvider.future);
    } catch (_) {
      if (mounted) {
        wtmSnack(context, l10n.wtmCreditsCheckFailed);
        setState(() => _busy = false);
      }
      return;
    }
    if (!mounted) return;
    if (!credits.isSubscriber) {
      setState(() => _busy = false);
      context.push(AppRoute.wtmPaywall);
      return;
    }
    if (!await confirmWtmEnhanceSpend(context, ref) || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    final refreshed = await runWtmEnhanceDialog(context, ref, item: _item);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _item = refreshed;
      _busy = false;
    });
  }

  /// Queue a free automatic re-run of the cutout (local BG §6.4).
  ///
  /// Distinct from [_fixCutout]: this asks the SERVER to try again, whereas Fix
  /// cutout opens the manual editor. The current cutout stays on screen throughout —
  /// the server does not clear it — so a failed improvement costs the user nothing.
  Future<void> _improveEdges(AppLocalizations l10n) async {
    if (_busy) return; // the local half of the duplicate-tap guard
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(wardrobeRepositoryProvider)
          .requestBiRefNetImprovement(_item.id);
      if (!mounted) return;
      setState(() => _item = updated);
      // Keep the closet in step so the card shows the same in-flight state.
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (mounted) wtmSnack(context, l10n.wardrobeImproveEdgesStarted);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open the free Erase/Restore editor; adopt the corrected item on return.
  Future<void> _fixCutout() async {
    final updated = await context.push<WardrobeItem>(
      AppRoute.wtmClosetFixCutout,
      extra: _item,
    );
    if (updated != null && mounted) setState(() => _item = updated);
  }

  Future<void> _edit(AppLocalizations l10n) async {
    final result = await showWtmGarmentEditSheet(context, item: _item);
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(wardrobeRepositoryProvider)
          .updateItem(
            _item.id,
            title: result.title,
            category: result.category,
            // Preserve the tagger's color — null would clear it server-side.
            color: _item.color,
          );
      if (!mounted) return;
      setState(() => _item = updated);
      await ref.read(wardrobeItemsProvider.notifier).refresh();
      if (mounted) wtmSnack(context, l10n.wtmGarmentSaved);
    } on ApiException catch (e) {
      if (mounted) wtmSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AppLocalizations l10n) async {
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmGarmentDeleteTitle,
      message: l10n.wtmGarmentDeleteMessage,
      confirmLabel: l10n.wtmGarmentDelete,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _deleting = true;
    });
    try {
      await ref.read(wardrobeRepositoryProvider).deleteItem(_item.id);
      ref.read(closetFavoritesProvider.notifier).remove(_item.id);
      // Instant local removal — the grid reflects it immediately, without the
      // slow full-closet refetch that made delete feel stuck (mobile QA #3).
      ref.read(wardrobeItemsProvider.notifier).removeItem(_item.id);
      if (!mounted) return;
      wtmSnack(context, l10n.wtmGarmentDeleted);
      wtmPageBack(context);
    } on ApiException catch (e) {
      if (mounted) {
        wtmSnack(context, e.message);
        setState(() {
          _busy = false;
          _deleting = false;
        });
      }
    }
  }
}

/// The Edit sheet's result — a null title clears the name.
typedef WtmGarmentEdit = ({String? title, String? category});

/// Name + category editor (WTM styling over the existing PATCH).
///
/// The category starts on the item's ACTUAL stored value, and only when that
/// value is one we offer. It used to start on whichever `ClosetCategory`
/// keyword-matched the stored text, which meant opening Edit on a mis-filed
/// piece re-affirmed the mistake: the wrong chip was already lit, so "review the
/// category" and "leave it exactly as it is" looked identical. An unrecognised
/// legacy value now selects nothing, states what is stored today, and asks.
Future<WtmGarmentEdit?> showWtmGarmentEditSheet(
  BuildContext context, {
  required WardrobeItem item,
}) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: item.title?.trim() ?? '');
  final stored = item.category?.trim();
  final known = garmentCategoryOf(stored);
  var category = known?.value;

  return showModalBottomSheet<WtmGarmentEdit>(
    context: context,
    backgroundColor: WtmColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WtmRadius.sheetTop),
      ),
    ),
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            WtmSpace.screenH,
            WtmSpace.s16,
            WtmSpace.screenH,
            WtmSpace.s18,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.wtmGarmentEditTitle,
                  textAlign: TextAlign.center,
                  style: WtmType.h1.copyWith(fontSize: 20),
                ),
                const SizedBox(height: WtmSpace.s14),
                TextField(
                  controller: controller,
                  style: WtmType.body,
                  cursorColor: WtmColors.gold,
                  decoration: InputDecoration(
                    hintText: l10n.wtmGarmentNameHint,
                    hintStyle: WtmType.body.copyWith(color: WtmColors.faint),
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
                      borderSide: const BorderSide(
                        color: WtmColors.chipOnBorder,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: WtmSpace.s16),
                WtmCategoryPicker(
                  selected: category,
                  legacyValue: known == null ? stored : null,
                  onChanged: (value) => setSheetState(() => category = value),
                ),
                const SizedBox(height: WtmSpace.s16),
                WtmTryOnTypeSummary(selected: category),
                const SizedBox(height: WtmSpace.s10),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    // An edit COMPLETES a piece: whatever it touches, the row it
                    // leaves behind has to have a name and a category the
                    // renderer can read. That is the same rule the API enforces
                    // on the merged row, so a disabled button here is the app
                    // agreeing with the server rather than guessing at it.
                    final ready =
                        value.text.trim().isNotEmpty &&
                        isChoosableGarmentCategory(category);
                    return GradientCta(
                      label: l10n.wtmGarmentSave,
                      onPressed: ready
                          ? () => Navigator.of(context).pop((
                              title: value.text.trim(),
                              category: category,
                            ))
                          : null,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
