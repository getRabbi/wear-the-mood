import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/product.dart';
import '../../features/discover/application/saved_products.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_product_card.dart';

/// The Saved screen (§11.3).
///
/// The list itself comes from [savedProductsProvider], which lives in the
/// application layer because Product Details writes to it too — a save made
/// there has to be reflected here without either screen knowing about the
/// other.
///
/// The server deliberately does NOT filter the list to currently-servable
/// products: something that sold out, or whose offer ended, has to show its
/// state rather than vanish without explanation. That is also why the cards
/// here keep their sold-out treatment instead of being hidden.
class WtmSavedScreen extends ConsumerStatefulWidget {
  const WtmSavedScreen({super.key});

  @override
  ConsumerState<WtmSavedScreen> createState() => _WtmSavedScreenState();
}

class _WtmSavedScreenState extends ConsumerState<WtmSavedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(analyticsProvider).track(AnalyticsEvents.savedOpen);
    });
  }

  /// Through the shared controller, not the repository directly: unsaving here
  /// has to put the heart back in the feed the user returns to as well, and
  /// only one place should know how that is done (§11.3).
  Future<void> _unsave(SavedProduct saved) async {
    try {
      await ref.read(savedOverridesProvider.notifier).toggle(saved.product);
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.productUnsave,
            properties: {DiscoverAnalyticsProps.productId: saved.product.id},
          );
    } catch (_) {
      if (!mounted) return;
      wtmSnack(context, AppLocalizations.of(context).errorGenericTitle);
    }
  }

  /// The card's Try On pill, through the one shared entry point (§13).
  ///
  /// Saved is where someone returns to decide, so it is the surface where
  /// "how would this actually look on me" is most worth one tap. The list
  /// keeps products that have since sold out, and those never carry the pill —
  /// the card only draws it for a product the server still calls try-on ready.
  void _tryOn(Product product) {
    final started = startShoppingTryOn(
      context,
      ref,
      product,
      placement: 'saved',
    );
    if (!started) {
      wtmSnack(context, AppLocalizations.of(context).wtmShopTryOnUnavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(savedProductsProvider);

    return WtmPage(
      title: l10n.wtmShopSavedTitle,
      eyebrow: l10n.wtmDiscoverTitle,
      children: saved.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 220),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmShopSavedTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(savedProductsProvider),
          ),
        ],
        data: (items) => items.isEmpty
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmEmptyState(
                  glyph: WtmGlyph.heart,
                  title: l10n.wtmShopSavedEmptyTitle,
                  message: l10n.wtmShopSavedEmptyMessage,
                ),
              ]
            : _grid(l10n, items),
      ),
    );
  }

  List<Widget> _grid(AppLocalizations l10n, List<SavedProduct> items) {
    final columns = MediaQuery.sizeOf(context).width >= 720 ? 3 : 2;
    final rows = <Widget>[];

    for (var i = 0; i < items.length; i += columns) {
      final slice = items.sublist(i, (i + columns).clamp(0, items.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: WtmSpace.s16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (c, saved) in slice.indexed) ...[
                if (c > 0) const SizedBox(width: WtmSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      WtmProductCard(
                        key: ValueKey(saved.product.id),
                        product: saved.product.copyWith(
                          saved: watchSaved(ref, saved.product),
                        ),
                        onToggleSave: () => _unsave(saved),
                        onTap: () => context.push(
                          '${AppRoute.wtmProductPath(saved.product.id)}&from=saved',
                          extra: saved.product,
                        ),
                        onTryOn: () => _tryOn(saved.product),
                      ),
                      // A real drop against the price stored when it was
                      // saved — derived server-side, never a client claim.
                      if (saved.priceDropped) ...[
                        const SizedBox(height: WtmSpace.s4),
                        Text(
                          l10n.wtmShopSavedPriceDropped,
                          maxLines: 2,
                          style: WtmType.micro.copyWith(
                            fontSize: 9,
                            color: WtmColors.gold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Keep the last row's columns honest when the count is odd.
              for (var pad = slice.length; pad < columns; pad++) ...[
                const SizedBox(width: WtmSpace.s10),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return rows;
  }
}
