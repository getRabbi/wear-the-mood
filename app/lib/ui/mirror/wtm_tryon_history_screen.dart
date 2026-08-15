import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/routes.dart';
import '../../data/models/tryon_result.dart';
import '../../data/repositories/tryon_repository.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../discover/wtm_restored_shop_actions.dart';
import '../widgets/widgets.dart';

/// Try-On History — every render the account has generated, newest first.
///
/// Deliberately NOT the same thing as Saved Looks, and the two are kept apart
/// on purpose:
///
/// | | Saved Looks | Try-On History |
/// |---|---|---|
/// | what it holds | renders the user chose to keep | every render they made |
/// | where it lives | this device, encrypted | the account, on the server |
/// | delete means | forget the record here | erase the row and its image |
///
/// The server has always kept this list (`GET /v1/tryon/results`); until now
/// the only screen that read it was the pre-Atelier Material one, reachable
/// solely from a push deep link. So the history existed and the user could not
/// get to it — which is what this screen fixes, without a new table, a second
/// engine, or a copy of anything.
class WtmTryOnHistoryScreen extends ConsumerStatefulWidget {
  const WtmTryOnHistoryScreen({super.key});

  @override
  ConsumerState<WtmTryOnHistoryScreen> createState() =>
      _WtmTryOnHistoryScreenState();
}

class _WtmTryOnHistoryScreenState extends ConsumerState<WtmTryOnHistoryScreen> {
  /// Ids with a delete in flight. A set rather than a bool so deleting one
  /// result never locks the rest of the grid, and so a second tap on the SAME
  /// tile cannot open a second confirmation.
  final _deleting = <String>{};

  /// Confirm, then delete for real.
  ///
  /// The notifier removes the tile on this frame and puts it back if the
  /// request fails, so the grid never sits still through a round trip and never
  /// claims a deletion that did not happen. A 404 is treated as success by the
  /// repository — the result is gone, which is what was asked for.
  Future<void> _delete(String id) async {
    if (_deleting.contains(id)) return;
    final l10n = AppLocalizations.of(context);

    setState(() => _deleting.add(id));
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.wtmTryOnHistoryDeleteConfirmTitle,
      message: l10n.wtmTryOnHistoryDeleteConfirmBody,
      confirmLabel: l10n.wtmTryOnHistoryDeleteConfirmAction,
      danger: true,
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _deleting.remove(id));
      return;
    }

    try {
      await ref.read(tryOnResultsProvider.notifier).delete(id);
      if (mounted) wtmSnack(context, l10n.wtmTryOnHistoryDeleted);
    } catch (_) {
      // The tile is already back; this says why it came back rather than
      // leaving the restore looking like a glitch.
      if (mounted) wtmSnack(context, l10n.wtmTryOnHistoryDeleteError);
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return WtmPage(
      title: l10n.wtmTryOnHistoryTitle,
      eyebrow: l10n.wtmTryOnHistoryEyebrow,
      children: ref
          .watch(tryOnResultsProvider)
          .when<List<Widget>>(
            // A refresh keeps the grid on screen rather than flashing skeletons
            // over renders the user is already looking at.
            skipLoadingOnReload: true,
            loading: () => const [_HistorySkeleton()],
            error: (_, _) => [
              const SizedBox(height: WtmSpace.s22),
              WtmErrorState(
                title: l10n.wtmTryOnHistoryErrorTitle,
                message: l10n.errorGenericTitle,
                retryLabel: l10n.commonRetry,
                onRetry: () => ref.invalidate(tryOnResultsProvider),
              ),
            ],
            data: (results) {
              // A result with no image is a row we cannot draw — a render whose
              // storage has expired, or a legacy row. Dropped rather than shown
              // as an empty tile.
              final items = [
                for (final r in results)
                  if ((r.resultImageUrl ?? '').isNotEmpty) r,
              ];
              if (items.isEmpty) {
                return [
                  const SizedBox(height: WtmSpace.s22),
                  WtmEmptyState(
                    glyph: WtmGlyph.sparkle,
                    title: l10n.wtmTryOnHistoryEmptyTitle,
                    message: l10n.wtmTryOnHistoryEmptyMessage,
                    ctaLabel: l10n.wtmTryOnHistoryEmptyCta,
                    onCta: () => context.push(AppRoute.wtmMirror),
                  ),
                ];
              }
              return [
                _Grid(items: items, deleting: _deleting, onDelete: _delete),
              ];
            },
          ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.items,
    required this.deleting,
    required this.onDelete,
  });

  final List<TryonResult> items;
  final Set<String> deleting;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 3 / 4,
      children: [
        for (final result in items)
          Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: l10n.wtmTryOnHistoryView,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      key: Key('wtm-tryon-open-${result.id}'),
                      onTap: () => _view(context, result, onDelete),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WtmRadius.tile),
                        child: CachedNetworkImage(
                          // The 512px rendition where the server has one. The
                          // full render is a whole-frame photo of a person and
                          // this tile is a third of the screen wide; capping the
                          // decode never stopped the whole thing downloading.
                          imageUrl: result.cardImageUrl!,
                          cacheKey: stableImageCacheKey(result.cardImageUrl!),
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
              // Delete on the tile itself — the grid is where somebody clearing
              // out old renders actually is. The viewer offers it too, for the
              // render already open full screen.
              Positioned(
                top: 2,
                right: 2,
                child: WtmIconButton(
                  WtmGlyph.erase,
                  key: Key('wtm-tryon-delete-${result.id}'),
                  semanticLabel: l10n.wtmTryOnHistoryDelete,
                  color: WtmColors.danger,
                  surface: WtmIconButtonSurface.image,
                  onTap: deleting.contains(result.id)
                      ? null
                      : () => onDelete(result.id),
                ),
              ),
              if (result.createdAt != null)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: _DateChip(date: result.createdAt!),
                ),
            ],
          ),
      ],
    );
  }
}

/// When the render was made, over the artwork. Small and low-contrast: it is
/// orientation for someone scanning months of renders, not a headline.
class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: WtmColors.panel,
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: WtmColors.line),
      ),
      child: Text(
        DateFormat.MMMd().format(date.toLocal()),
        style: WtmType.micro.copyWith(fontSize: 9),
      ),
    );
  }
}

/// The render, full screen and zoomable.
///
/// Carries the same two actions the Saved Looks viewer does — the shopping
/// back-link for a render that came from a product, and delete — so a result
/// opened from history behaves exactly like one opened from anywhere else.
void _view(
  BuildContext context,
  TryonResult result,
  Future<void> Function(String id) onDelete,
) {
  final url = result.resultImageUrl!;
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
                    surface: WtmIconButtonSurface.image,
                    semanticLabel: MaterialLocalizations.of(
                      dialogContext,
                    ).backButtonTooltip,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                  const Spacer(),
                  // Closes the viewer FIRST so the confirmation and its result
                  // land on the grid — a dialog stacked on a full-screen dialog
                  // is where "did that work?" comes from.
                  WtmIconButton(
                    WtmGlyph.erase,
                    key: const Key('wtm-tryon-viewer-delete'),
                    semanticLabel: AppLocalizations.of(
                      dialogContext,
                    ).wtmTryOnHistoryDelete,
                    color: WtmColors.danger,
                    surface: WtmIconButtonSurface.image,
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      onDelete(result.id);
                    },
                  ),
                ],
              ),
            ),
          ),
          // A render that came from a PRODUCT gets its shopping actions back
          // here, restored from the job rather than from anything this device
          // remembered (§13).
          if (result.source case final origin?)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(WtmSpace.screenH),
                  child: WtmRestoredShopActions(
                    // The row already carries its origin, so this needs no
                    // second round trip to learn what it was of.
                    source: ShoppingTryOnSource.restored(origin),
                    onNavigate: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Never a bare spinner (§4.3): the grid's own shape, in shimmer.
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 3 / 4,
      children: [
        for (var i = 0; i < 6; i++)
          LoadingShimmer(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(WtmRadius.tile),
          ),
      ],
    );
  }
}
