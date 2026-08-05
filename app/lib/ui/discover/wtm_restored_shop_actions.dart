import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/discover/application/product_details.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/uuid.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// The shopping actions on a REOPENED try-on result (DISCOVER §13, Phase 5.1).
///
/// Given only a job id — the one thing Saved Looks persists on device — this
/// asks the server what the render was of and, if it was a product, offers the
/// way back to it and out to the store.
///
/// Renders NOTHING at all for an ordinary closet look, for a look whose product
/// has since been withdrawn, and while the answer is still in flight. A history
/// tile must open the same way it always did; shopping actions are an addition
/// that appears when it can, never a delay or a placeholder.
///
/// What it deliberately does not do is trust anything cached. The origin gives
/// it a product ID and nothing else: price, stock and the destination are all
/// re-read live through the Phase 4 endpoints at the moment the user acts, so a
/// look saved weeks ago cannot show a stale price or open a dead link (§35).
class WtmRestoredShopActions extends ConsumerStatefulWidget {
  const WtmRestoredShopActions({
    super.key,
    required this.jobId,
    this.onNavigate,
  });

  final String jobId;

  /// Called just before routing away — lets a host dialog close itself first.
  final VoidCallback? onNavigate;

  @override
  ConsumerState<WtmRestoredShopActions> createState() =>
      _WtmRestoredShopActionsState();
}

class _WtmRestoredShopActionsState
    extends ConsumerState<WtmRestoredShopActions> {
  /// One key per mount, so a retry after a dropped response replays the same
  /// click rather than logging a second one (§9).
  String _clickKey = uuidV4();
  bool _opening = false;
  ShopFailure? _failure;

  void _openProduct(ShoppingTryOnSource source) {
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.productOpen,
          properties: {
            DiscoverAnalyticsProps.productId: source.productId,
            DiscoverAnalyticsProps.feedPlacement: _placement,
          },
        );
    widget.onNavigate?.call();
    context.push(
      '${AppRoute.wtmProductPath(source.productId)}&from=$_placement',
    );
  }

  /// The Phase 4 contract, unchanged: the backend records the click and returns
  /// the one destination it has already validated against the merchant's domain
  /// allow-list. A product that is gone answers 404 and shows the unavailable
  /// state rather than opening anything.
  Future<void> _shop(ShoppingTryOnSource source) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failure = null;
    });
    try {
      final click = await ref
          .read(discoverRepositoryProvider)
          .click(
            source.productId,
            idempotencyKey: _clickKey,
            feedPlacement: _placement,
            campaignId: source.campaignId,
          );
      final opened = await ref.read(linkLauncherProvider).open(click.url);
      if (!mounted) return;
      if (!opened) {
        setState(() => _failure = ShopFailure.unreachable);
        return;
      }
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.affiliateClick,
            properties: {
              DiscoverAnalyticsProps.productId: source.productId,
              DiscoverAnalyticsProps.merchantId: click.merchant.id,
              DiscoverAnalyticsProps.feedPlacement: _placement,
              DiscoverAnalyticsProps.tryOnCompleted: click.tryOnCompleted,
            },
          );
      _clickKey = uuidV4();
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = shopFailureFor(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  static const _placement = 'tryon_result';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final source = ref
        .watch(savedLookSourceProvider(widget.jobId))
        .asData
        ?.value;
    // Loading, an ordinary look, an unresolvable job, a withdrawn product —
    // all the same answer here: this is just a look.
    if (source == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_failure != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s12,
              vertical: WtmSpace.s8,
            ),
            decoration: BoxDecoration(
              color: WtmColors.chipBg,
              border: Border.all(color: WtmColors.line),
              borderRadius: BorderRadius.circular(WtmRadius.chip),
            ),
            child: Text(
              _failure == ShopFailure.unavailable
                  // The product is gone. Saying so beats opening a dead page,
                  // and View Product still works — it shows the same state
                  // with alternatives underneath (§24).
                  ? l10n.wtmShopUnavailableTitle
                  : l10n.wtmShopStoreUnreachable,
              style: WtmType.micro.copyWith(color: WtmColors.text),
            ),
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        // Wrap, not Row: two natural-width pills overflow a 360dp screen by
        // 58px, and they grow further with the user's text scale. Stacking is
        // the right answer over someone's photograph — clipping is not.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: WtmSpace.s10,
          runSpacing: WtmSpace.s8,
          children: [
            GoldPill(
              label: l10n.wtmShopViewProduct,
              icon: const WtmIcon(
                WtmGlyph.search,
                size: 12,
                color: WtmColors.gold,
              ),
              onTap: () => _openProduct(source),
            ),
            GoldPill(
              label: _opening
                  ? l10n.wtmShopOpeningStore
                  : l10n.wtmShopShopAtStore,
              icon: const WtmIcon(
                WtmGlyph.store,
                size: 12,
                color: WtmColors.gold,
              ),
              onTap: _opening ? null : () => _shop(source),
            ),
          ],
        ),
      ],
    );
  }
}
