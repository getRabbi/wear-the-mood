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
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../widgets/widgets.dart';
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
  bool _deleting = false; // drives the "Deleting…" button feedback (mobile QA #3)

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
                  child: GestureDetector(
                    onTap: () => ref
                        .read(closetFavoritesProvider.notifier)
                        .toggle(_item.id),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: WtmColors.addRingBg,
                        border: Border.all(color: WtmColors.addRingBorder),
                      ),
                      alignment: Alignment.center,
                      child: WtmIcon(
                        WtmGlyph.heart,
                        size: 15,
                        color: favorite
                            ? WtmColors.gold
                            : WtmColors.addRingIcon,
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
            if (_item.category?.trim().isNotEmpty ?? false)
              WtmChip(label: _item.category!.trim(), on: true),
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
          onPressed: () {
            // Queue this piece so Step 2 opens pre-filled (§8 handoff).
            ref.read(tryOnPreselectProvider.notifier).setItem(_item);
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
Future<WtmGarmentEdit?> showWtmGarmentEditSheet(
  BuildContext context, {
  required WardrobeItem item,
}) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: item.title?.trim() ?? '');
  var category = ClosetCategory.values.firstWhere(
    (c) =>
        c != ClosetCategory.all &&
        c != ClosetCategory.favorites &&
        c.matches(item.category),
    orElse: () => ClosetCategory.all,
  );

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
                const SizedBox(height: WtmSpace.s12),
                Wrap(
                  spacing: WtmSpace.s6,
                  runSpacing: WtmSpace.s6,
                  children: [
                    for (final c in ClosetCategory.values)
                      if (c != ClosetCategory.all &&
                          c != ClosetCategory.favorites)
                        WtmChip(
                          label: c.label(l10n),
                          on: category == c,
                          onTap: () => setSheetState(() => category = c),
                        ),
                  ],
                ),
                const SizedBox(height: WtmSpace.s16),
                GradientCta(
                  label: l10n.wtmGarmentSave,
                  onPressed: () {
                    final title = controller.text.trim();
                    Navigator.of(context).pop((
                      title: title.isEmpty ? null : title,
                      category: category == ClosetCategory.all
                          ? item.category
                          : category.name,
                    ));
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
