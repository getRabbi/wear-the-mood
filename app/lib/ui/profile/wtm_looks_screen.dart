import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/collections/local_collections.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../community/wtm_compose_screen.dart' show WtmComposeArgs;
import '../discover/wtm_restored_shop_actions.dart';
import '../widgets/widgets.dart';

/// Saved Looks gallery (board §3.6, P7) — the durable try-on renders saved from
/// the Result screen ([savedLookRecordsProvider]). A tile opens the look
/// full-screen (zoomable). Empty → an invitation to run the mirror.
class WtmLooksScreen extends ConsumerStatefulWidget {
  const WtmLooksScreen({super.key});

  @override
  ConsumerState<WtmLooksScreen> createState() => _WtmLooksScreenState();
}

class _WtmLooksScreenState extends ConsumerState<WtmLooksScreen> {
  /// Ids currently being removed. A set rather than a bool so deleting one look
  /// never locks the rest of the grid, and so a second tap on the SAME tile
  /// cannot open a second confirmation.
  final _deleting = <String>{};

  /// Remove a saved look.
  ///
  /// **Local only.** A saved look is a device-local record in encrypted storage
  /// (per-user namespaced), so there is no endpoint, no row and no RLS involved
  /// — the owner check is structural.
  ///
  /// The durable render in R2 is deliberately LEFT ALONE: "Share Look" can put
  /// that exact URL into a community post, and deleting the object would blank
  /// an already-published post belonging to a conversation this screen knows
  /// nothing about. Removing the record is the whole operation.
  Future<void> _delete(String id) async {
    if (_deleting.contains(id)) return;
    final l10n = AppLocalizations.of(context);
    final store = ref.read(savedLookRecordsProvider.notifier);
    // Already gone (a stale tile, a double tap that raced) — succeed quietly
    // rather than asking the user to confirm deleting nothing.
    if (!store.contains(id)) return;

    setState(() => _deleting.add(id));
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmLooksDeleteConfirmTitle,
      message: l10n.wtmLooksDeleteConfirmBody,
      confirmLabel: l10n.wtmLooksDeleteConfirmAction,
      danger: true,
    );
    if (!mounted) return;
    setState(() => _deleting.remove(id));
    if (!confirmed) return;

    // Synchronous and idempotent: the store drops the record and persists, and
    // every surface watching it (this grid, the profile count, Home's rail)
    // rebuilds on the same frame. There is no request to roll back.
    store.remove(id);
    if (mounted) wtmSnack(context, l10n.wtmLooksDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final looks = ref.watch(savedLookRecordsProvider);

    return WtmPage(
      title: l10n.wtmLooksTitle,
      eyebrow: l10n.wtmLooksEyebrow,
      children: [
        if (looks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WtmSpace.s22),
            child: WtmEmptyState(
              glyph: WtmGlyph.sparkle,
              title: l10n.wtmLooksEmptyTitle,
              message: l10n.wtmLooksEmptyMessage,
              ctaLabel: l10n.wtmLooksEmptyCta,
              onCta: () => context.push(AppRoute.wtmMirror),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 3 / 4,
            children: [
              for (final look in looks)
                Stack(
                  children: [
                    Positioned.fill(
                      child: Semantics(
                        button: true,
                        label: l10n.wtmLooksView,
                        child: ExcludeSemantics(
                          child: GestureDetector(
                            key: Key('wtm-look-open-${look.id}'),
                            // The look's id IS the try-on job id, which is what
                            // makes restoration possible: the origin comes back
                            // off the server with the job, long after the
                            // process that created it died (§13).
                            onTap: () => _view(context, look.imageUrl, look.id),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                WtmRadius.tile,
                              ),
                              child: CachedNetworkImage(
                                imageUrl: look.imageUrl,
                                cacheKey: stableImageCacheKey(look.imageUrl),
                                fit: BoxFit.cover,
                                // 3-across grid — cap the decode (mobile QA #1).
                                memCacheWidth: 480,
                                placeholder: (_, _) => const AuroraBox(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(WtmRadius.tile),
                                  ),
                                ),
                                errorWidget: (_, _, _) => const AuroraBox(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(WtmRadius.tile),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Delete, on the tile itself — the grid is where someone
                    // clearing out old renders actually is. The viewer offers
                    // it too, for the look already open full screen.
                    Positioned(
                      top: 2,
                      right: 2,
                      child: WtmIconButton(
                        WtmGlyph.erase,
                        key: Key('wtm-look-delete-${look.id}'),
                        semanticLabel: l10n.wtmLooksDelete,
                        color: WtmColors.danger,
                        onTap: _deleting.contains(look.id)
                            ? null
                            : () => _delete(look.id),
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  void _view(BuildContext context, String url, String jobId) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xF2050308),
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: url,
                cacheKey: stableImageCacheKey(url),
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Center(
                  child: WtmIcon(
                    WtmGlyph.sparkle,
                    size: 40,
                    color: WtmColors.faint,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(WtmSpace.screenH),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WtmIconButton(
                      WtmGlyph.back,
                      semanticLabel: MaterialLocalizations.of(
                        dialogContext,
                      ).backButtonTooltip,
                      onTap: () => Navigator.of(dialogContext).pop(),
                    ),
                    const Spacer(),
                    // Same delete, from the look someone is actually looking
                    // at. Closes the viewer FIRST so the confirmation and the
                    // result land on the grid — a dialog stacked on a
                    // full-screen dialog is where "did that work?" comes from.
                    WtmIconButton(
                      WtmGlyph.erase,
                      key: const Key('wtm-look-viewer-delete'),
                      semanticLabel: AppLocalizations.of(
                        dialogContext,
                      ).wtmLooksDelete,
                      color: WtmColors.danger,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        _delete(jobId);
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Share Look → Create Post prefilled with this render. Pops with
            // the dialog's context, routes with the screen's (still mounted).
            //
            // A look that came from a PRODUCT also gets its shopping actions
            // back here — this is the surface someone actually returns to days
            // later, and the origin is restored from the job rather than from
            // anything this device remembered (§13).
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(WtmSpace.screenH),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WtmRestoredShopActions(
                        jobId: jobId,
                        onNavigate: () => Navigator.of(dialogContext).pop(),
                      ),
                      const SizedBox(height: WtmSpace.s10),
                      GoldPill(
                        label: AppLocalizations.of(dialogContext).wtmShareLook,
                        icon: const WtmIcon(
                          WtmGlyph.users,
                          size: 12,
                          color: WtmColors.gold,
                        ),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          context.push(
                            AppRoute.wtmCompose,
                            extra: WtmComposeArgs(imageUrl: url),
                          );
                        },
                      ),
                    ],
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
