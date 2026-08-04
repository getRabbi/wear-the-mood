import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/product.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/domain/discover_feed.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_feed_modules.dart';
import 'wtm_impression.dart';
import 'wtm_product_card.dart';
import 'wtm_shop_filter_sheet.dart';

/// The `Picked for You` section: heading, filter affordance, and the composed
/// product/module feed (DISCOVER §8).
///
/// Lives inside the Discover screen's single scroll view rather than owning
/// one. A grid nested in a list needs `shrinkWrap` and its own physics, and two
/// scrollables with conflicting physics is exactly the nested-scroll conflict
/// §15 and §41 call out — so the feed is composed into ROWS and emitted as
/// plain children.
class WtmShopFeed extends ConsumerStatefulWidget {
  const WtmShopFeed({
    super.key,
    this.modules = const [],
    this.railStoryIds = const {},
    required this.onOpenStory,
  });

  /// Stories eligible to appear as full-width feed modules.
  final List<DiscoverStory> modules;

  /// Stories already in the rail above; excluded from the first module slot so
  /// the same campaign is not in one viewport twice (§33.3).
  final Set<String> railStoryIds;

  final void Function(DiscoverStory story) onOpenStory;

  @override
  ConsumerState<WtmShopFeed> createState() => _WtmShopFeedState();
}

class _WtmShopFeedState extends ConsumerState<WtmShopFeed> {
  /// Fire-and-forget: a behavioural signal is not worth interrupting a scroll
  /// for, and the server deduplicates retries anyway.
  void _record(
    String eventType, {
    Product? product,
    String placement = 'feed_grid',
  }) {
    ref
        .read(discoverRepositoryProvider)
        .recordInteraction(
          eventType: eventType,
          productId: product?.id,
          merchantId: product?.merchant.id,
          feedPlacement: placement,
          trackingToken: product?.trackingToken,
          // Stable per (product, event) for this session, so a retry after a
          // dropped response is the same row rather than a second signal.
          clientEventId: product == null
              ? null
              : '$eventType:${product.id}:${identityHashCode(this)}',
        )
        .catchError((Object _) {
          // A lost analytics write must never surface to someone browsing.
        });
  }

  Future<void> _toggleSave(Product product) async {
    final saving = !product.saved;
    try {
      await ref.read(productFeedProvider.notifier).toggleSave(product);
      _record(saving ? 'save' : 'unsave', product: product);
      ref
          .read(analyticsProvider)
          .track(
            saving
                ? AnalyticsEvents.productSave
                : AnalyticsEvents.productUnsave,
            properties: {DiscoverAnalyticsProps.productId: product.id},
          );
    } catch (_) {
      if (!mounted) return;
      // The optimistic heart has already been put back by the notifier; this
      // just says so rather than leaving the tap looking ignored.
      wtmSnack(context, AppLocalizations.of(context).errorGenericTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = ref.watch(productFeedProvider);
    final filters = ref.watch(productFiltersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
          child: Row(
            children: [
              // Flexible, not a fixed Text + Spacer: this heading is a
              // translated string and the filter label grows once filters are
              // applied, so on a small phone the pair overflowed. It has to
              // give way rather than push the control off the screen.
              Flexible(
                child: Text(
                  l10n.wtmShopPickedForYou,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.h2,
                ),
              ),
              const SizedBox(width: WtmSpace.s10),
              const Spacer(),
              // A compact indicator, never a permanent chip row (§11.2, §26.1).
              _FilterButton(
                label: filters.activeCount == 0
                    ? l10n.wtmShopFilter
                    : l10n.wtmShopFilterCount(filters.activeCount),
                active: filters.activeCount > 0,
                onTap: () => showWtmShopFilterSheet(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
        ...feed.when<List<Widget>>(
          skipLoadingOnReload: true,
          loading: _skeleton,
          error: (_, _) => [
            WtmErrorState(
              title: l10n.wtmDiscoverErrorTitle,
              message: l10n.errorGenericTitle,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(productFeedProvider),
            ),
          ],
          data: (state) => _feed(l10n, state, filters.hasAny),
        ),
      ],
    );
  }

  List<Widget> _feed(
    AppLocalizations l10n,
    ProductFeedState state,
    bool filtered,
  ) {
    if (state.isEmpty) return _empty(l10n, state, filtered);

    final closet = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final items = DiscoverFeedComposer.compose(
      products: state.items,
      modules: widget.modules,
      completeLook: DiscoverFeedComposer.completeLook(
        closet: closet,
        products: state.items,
      ),
      railStoryIds: widget.railStoryIds,
      columns: _columnsFor(MediaQuery.sizeOf(context).width),
    );

    return [
      for (final item in items) ...[
        _row(l10n, item),
        const SizedBox(height: WtmSpace.s16),
      ],
      // Loading the next page shows a quiet footer, never a full-screen
      // spinner over content the user is reading (§23, §24).
      if (state.loadingMore)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
          child: LoadingShimmer(width: double.infinity, height: 90),
        ),
      if (state.loadMoreFailed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.wtmShopLoadMoreFailed, style: WtmType.micro),
              ),
              GhostButton(
                label: l10n.commonRetry,
                onPressed: () =>
                    ref.read(productFeedProvider.notifier).loadMore(),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _row(AppLocalizations l10n, DiscoverFeedItem item) {
    // Exhaustive over the sealed hierarchy: a new feed item type is a compile
    // error here rather than a blank row found in QA (§16).
    return switch (item) {
      ProductRowItem(:final products) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, product) in products.indexed) ...[
              if (i > 0) const SizedBox(width: WtmSpace.s10),
              Expanded(
                child: WtmImpression(
                  impressionKey: 'product:${product.id}',
                  onImpression: () {
                    _record('impression', product: product);
                    ref
                        .read(analyticsProvider)
                        .track(
                          AnalyticsEvents.productImpression,
                          properties: {
                            DiscoverAnalyticsProps.productId: product.id,
                            DiscoverAnalyticsProps.merchantId:
                                product.merchant.id,
                          },
                        );
                  },
                  child: WtmProductCard(
                    key: ValueKey(product.id),
                    product: product,
                    onToggleSave: () => _toggleSave(product),
                    // Product Details is Phase 4 and shopping Try-On is Phase
                    // 5. Both stay null rather than pointing at a screen that
                    // does not exist yet.
                  ),
                ),
              ),
            ],
            // A trailing odd product must not stretch to full width; an empty
            // Expanded keeps the grid columns honest.
            if (products.length == 1) ...[
              const SizedBox(width: WtmSpace.s10),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      ),
      CompleteLookItem() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
        child: WtmCompleteLookModule(
          item: item,
          onCta: () {
            ref.read(analyticsProvider).track(AnalyticsEvents.completeLookOpen);
            context.push(AppRoute.wtmCloset);
          },
        ),
      ),
      StoryModuleItem(:final story) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
        child: WtmStoryModule(
          story: story,
          ctaLabel: switch (story.type) {
            DiscoverStoryType.giveaway => l10n.wtmStoryCtaViewGiveaway,
            DiscoverStoryType.offer => l10n.wtmStoryCtaViewOffer,
            DiscoverStoryType.newsroom => l10n.wtmStoryCtaReadStory,
            _ => l10n.wtmStoryCtaOpen,
          },
          onCta: () => widget.onOpenStory(story),
        ),
      ),
    };
  }

  List<Widget> _empty(
    AppLocalizations l10n,
    ProductFeedState state,
    bool filtered,
  ) {
    // Three genuinely different empty states. Telling a user in an unsupported
    // country to "remove a filter" would be useless advice (§24).
    if (state.regionEmpty) {
      return [
        WtmEmptyState(
          glyph: WtmGlyph.store,
          title: l10n.wtmShopRegionEmptyTitle,
          message: l10n.wtmShopRegionEmptyMessage,
        ),
      ];
    }
    if (filtered) {
      return [
        WtmEmptyState(
          glyph: WtmGlyph.filter,
          title: l10n.wtmShopEmptyTitle,
          message: l10n.wtmShopEmptyMessage,
          ctaLabel: l10n.wtmShopFilterReset,
          onCta: () => ref.read(productFiltersProvider.notifier).reset(),
        ),
      ];
    }
    // Cold start: never a blank feed, and never a setup flow standing between
    // the user and Discover (§19.5).
    return [
      WtmEmptyState(
        glyph: WtmGlyph.sparkle,
        title: l10n.wtmShopColdStartTitle,
        message: l10n.wtmShopColdStartMessage,
      ),
    ];
  }

  List<Widget> _skeleton() => [
    for (var i = 0; i < 2; i++) ...[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
        child: Row(
          children: [
            for (var c = 0; c < 2; c++) ...[
              if (c > 0) const SizedBox(width: WtmSpace.s10),
              const Expanded(
                child: AspectRatio(
                  aspectRatio: 0.74,
                  child: LoadingShimmer(
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
    ],
  ];

  /// Two columns on a phone, more on a tablet — without letting a card grow
  /// into a banner (§41).
  static int _columnsFor(double width) {
    if (width >= 1000) return 4;
    if (width >= 720) return 3;
    return 2;
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WtmSpace.s10,
              vertical: WtmSpace.s6,
            ),
            decoration: BoxDecoration(
              color: active ? WtmColors.chipOnBg : WtmColors.chipBg,
              border: Border.all(
                color: active ? WtmColors.chipOnBorder : WtmColors.line,
              ),
              borderRadius: BorderRadius.circular(WtmRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WtmIcon(
                  WtmGlyph.filter,
                  size: 13,
                  color: active ? WtmColors.gold : WtmColors.muted,
                ),
                const SizedBox(width: WtmSpace.s6),
                Text(
                  label,
                  style: WtmType.chip.copyWith(
                    color: active ? WtmColors.gold : WtmColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
