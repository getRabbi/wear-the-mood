import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/outfit.dart';
import '../../data/repositories/outfit_repository.dart';
import '../../features/outfits/outfit_providers.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../mirror/wtm_tryon_handoff.dart';
import '../widgets/widgets.dart';
import 'wtm_outfits_screen.dart' show wardrobeById;
import 'wtm_outfit_composer.dart';

/// Outfit detail (board §3.19, P5) — the saved outfit's pieces (resolved from
/// the closet), Try It On (→ MoodMirror Step 2), Edit (pre-fills the composer)
/// and Delete (real, confirmed). Reached with the [Outfit] as the route extra.
class WtmOutfitDetailScreen extends ConsumerStatefulWidget {
  const WtmOutfitDetailScreen({super.key, required this.outfit});

  final Outfit outfit;

  @override
  ConsumerState<WtmOutfitDetailScreen> createState() =>
      _WtmOutfitDetailScreenState();
}

class _WtmOutfitDetailScreenState extends ConsumerState<WtmOutfitDetailScreen> {
  bool _busy = false;

  Outfit get _outfit => widget.outfit;

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmOutfitDeleteTitle,
      message: l10n.wtmOutfitDeleteMessage,
      confirmLabel: l10n.wtmOutfitDelete,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(outfitRepositoryProvider).deleteOutfit(_outfit.id);
      ref.invalidate(outfitsProvider);
      if (mounted) {
        wtmSnack(context, l10n.wtmOutfitDeleted);
        wtmPageBack(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        wtmSnack(context, l10n.wtmOutfitsSaveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final byId = wardrobeById(
      ref.watch(wardrobeItemsProvider).asData?.value ?? const [],
    );
    final pieces = [
      for (final id in _outfit.itemIds)
        if (byId[id] != null) byId[id]!,
    ];
    final name = (_outfit.name ?? '').trim();

    return WtmPage(
      title: name.isEmpty ? l10n.wtmOutfitsUntitled : name,
      eyebrow: l10n.wtmOutfitDetailEyebrow,
      children: [
        if (pieces.isEmpty)
          WtmEmptyState(
            glyph: WtmGlyph.hanger,
            title: l10n.wtmOutfitMissingTitle,
            message: l10n.wtmOutfitMissingMessage,
            ctaLabel: l10n.wtmStylistEmptyCta,
            onCta: () => context.push(AppRoute.wtmClosetAdd),
          )
        else ...[
          Row(
            children: [
              for (final (i, item) in pieces.take(4).indexed) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: FabricTile(
                    imageUrl: item.displayImageUrl,
                    swatchIndex: i + 2,
                    fit: BoxFit.contain,
                    semanticLabel: item.title,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: WtmSpace.s16),
          GradientCta(
            label: l10n.wtmOutfitTryOn,
            icon: const WtmIcon(WtmGlyph.sparkle,
                size: 15, color: WtmColors.ctaText),
            onPressed: _busy
                ? null
                : () {
                    if (!wtmTryOnWithItems(context, ref, pieces)) {
                      wtmSnack(context, l10n.wtmTryOnNoImage);
                    }
                  },
          ),
          const SizedBox(height: WtmSpace.s10),
          // Share Look → Create Post prefilled with THIS outfit (cover image
          // when it has one, else its first piece) — never a MoodMirror detour.
          GhostButton(
            label: l10n.wtmShareLook,
            icon: const WtmIcon(WtmGlyph.users, size: 15, color: WtmColors.text),
            onPressed: _busy
                ? null
                : () => context.push(
                      AppRoute.wtmCompose,
                      extra: WtmComposeArgs(
                        imageUrl: _outfit.coverImageUrl ??
                            pieces.first.displayImageUrl,
                        outfitId: _outfit.id,
                      ),
                    ),
          ),
          const SizedBox(height: WtmSpace.s10),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: l10n.wtmOutfitEdit,
                  onPressed: _busy
                      ? null
                      : () {
                          ref
                              .read(wtmOutfitComposerProvider.notifier)
                              .loadForEdit(_outfit);
                          wtmSnack(context, l10n.wtmOutfitEditing);
                          wtmPageBack(context);
                        },
                ),
              ),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: GhostButton(
                  label: l10n.wtmOutfitDelete,
                  foregroundColor: WtmColors.danger,
                  onPressed: _busy ? null : _delete,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
