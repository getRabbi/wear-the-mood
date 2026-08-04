import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../data/models/product.dart';
import '../../data/repositories/discover_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_product_card.dart';

/// Saved products, newest first.
///
/// The server deliberately does NOT filter this list to currently-servable
/// products: something that sold out, or whose offer ended, has to show its
/// state rather than vanish without explanation (§11.3). That is also why the
/// cards here keep their sold-out treatment instead of being hidden.
final savedProductsProvider = FutureProvider.autoDispose<List<SavedProduct>>((
  ref,
) {
  return ref.watch(discoverRepositoryProvider).saved();
});

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

  Future<void> _unsave(SavedProduct saved) async {
    try {
      await ref.read(discoverRepositoryProvider).unsave(saved.product.id);
      ref.invalidate(savedProductsProvider);
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
                        product: saved.product,
                        onToggleSave: () => _unsave(saved),
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
