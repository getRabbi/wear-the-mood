import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/product.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/application/saved_products.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../features/discover/domain/discover_feed.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_discover_sections.dart';
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
/// §15 and §41 call out — so the feed is composed into BANDS and emitted as
/// plain children.
///
/// Each product band is a short horizontal strip under its own heading, never
/// an open-ended grid: that is what the approved layout asks for, and it is
/// what keeps a paginated catalog from reading as a marketplace wall.
class WtmShopFeed extends ConsumerStatefulWidget {
  const WtmShopFeed({
    super.key,
    this.modules = const [],
    required this.onOpenStory,
  });

  /// Stories eligible to appear as full-width feed modules.
  ///
  /// The same campaigns the rail shows. §33.3 permits a campaign in both
  /// places when a campaign rule calls for it, and the approved layout does:
  /// the rail card is a glance, the feed card is the editorial pitch with its
  /// own heading and action.
  final List<DiscoverStory> modules;

  final void Function(DiscoverStory story) onOpenStory;

  @override
  ConsumerState<WtmShopFeed> createState() => _WtmShopFeedState();
}

/// Discover's gutter — the prototype's `--pad`, which tightens under its
/// 350px breakpoint. Shared by every band so nothing sits a few pixels off the
/// column the rest of the surface keeps.
double _pad(BuildContext context) =>
    DiscoverTokens.padFor(MediaQuery.sizeOf(context).width);

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

  /// The card's Try On badge (§13). Straight into the existing MoodMirror
  /// pipeline — no confirmation step, because the flow's own body and mode
  /// steps come next and nothing has been spent yet.
  void _tryOn(Product product) {
    final started = startShoppingTryOn(
      context,
      ref,
      product,
      placement: 'feed_grid',
    );
    if (!started) {
      wtmSnack(context, AppLocalizations.of(context).wtmShopTryOnUnavailable);
    }
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
        // The lead band's heading lives here rather than inside the composed
        // feed, so the filter affordance stays reachable while the feed is
        // loading, empty or errored.
        WtmSectionHead(
          eyebrow: l10n.wtmShopStripPickedEyebrow,
          title: l10n.wtmShopPickedForYou,
          // A compact indicator, never a permanent chip row (§11.2, §26.1).
          trailing: _FilterButton(
            label: filters.activeCount == 0
                ? l10n.wtmShopFilter
                : l10n.wtmShopFilterCount(filters.activeCount),
            active: filters.activeCount > 0,
            onTap: () => showWtmShopFilterSheet(context, ref),
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
      completeLooks: DiscoverFeedComposer.completeLooks(
        closet: closet,
        products: state.items,
      ),
    );

    return [
      // Cached data after a failed fetch. Non-blocking, and explicit that the
      // prices are not current — a stale price shown as live is worse than no
      // feed at all (§24, §35).
      if (state.fromCache) ...[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
          child: Row(
            children: [
              const WtmIcon(WtmGlyph.shield, size: 13, color: WtmColors.muted),
              const SizedBox(width: WtmSpace.s6),
              Expanded(child: Text(l10n.wtmShopOffline, style: WtmType.micro)),
            ],
          ),
        ),
        const SizedBox(height: WtmSpace.s12),
      ],
      for (final item in items) ...[
        _band(l10n, item),
        const SizedBox(height: DiscoverTokens.sectionGap),
      ],
      // Loading the next page shows a quiet footer, never a full-screen
      // spinner over content the user is reading (§23, §24).
      if (state.loadingMore)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
          child: LoadingShimmer(width: double.infinity, height: 90),
        ),
      if (state.loadMoreFailed)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
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

  Widget _band(AppLocalizations l10n, DiscoverFeedItem item) {
    // Exhaustive over the sealed hierarchy: a new feed item type is a compile
    // error here rather than a blank band found in QA (§16).
    return switch (item) {
      ProductStripItem() => _strip(l10n, item),
      CompleteLookItem() => Padding(
        padding: EdgeInsets.symmetric(horizontal: _pad(context)),
        child: WtmCompleteLookModule(
          item: item,
          onCta: () {
            ref.read(analyticsProvider).track(AnalyticsEvents.completeLookOpen);
            context.push(AppRoute.wtmCloset);
          },
        ),
      ),
      StoryModuleItem(:final story) => _storyBand(l10n, story),
    };
  }

  /// One curated product band: its heading (except the lead band, whose
  /// heading carries the filter control and is emitted above the feed) and a
  /// horizontal strip of at most four cards.
  Widget _strip(AppLocalizations l10n, ProductStripItem item) {
    final cards = [
      for (final product in item.products)
        WtmImpression(
          impressionKey: 'product:${product.id}',
          onImpression: () {
            _record('impression', product: product);
            ref
                .read(analyticsProvider)
                .track(
                  AnalyticsEvents.productImpression,
                  properties: {
                    DiscoverAnalyticsProps.productId: product.id,
                    DiscoverAnalyticsProps.merchantId: product.merchant.id,
                  },
                );
          },
          child: WtmProductCard(
            key: ValueKey(product.id),
            // The override layer wins, so a save made on Product Details is
            // already reflected when the user comes back — without reloading
            // page 1 and throwing away their scroll position (§33.2).
            product: product.copyWith(saved: watchSaved(ref, product)),
            onToggleSave: () => _toggleSave(product),
            // `push`, not `go`: Discover stays alive underneath with its
            // scroll offset and every loaded page intact, and back returns
            // exactly there (§33.2, §41).
            onTap: () => context.push(
              '${AppRoute.wtmProductPath(product.id)}&from=feed_grid',
              extra: product,
            ),
            // The card's Try On badge only renders for a product whose
            // compatibility has actually passed, so this is wired for all of
            // them; the adapter still refuses anything without a usable image
            // rather than opening a flow that would fail.
            onTryOn: () => _tryOn(product),
          ),
        ),
    ];

    if (item.slot == DiscoverStripSlot.pickedForYou) {
      return WtmProductStrip(cards: cards);
    }

    final more = item.slot == DiscoverStripSlot.moreForYou;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WtmSectionHead(
          eyebrow: more
              ? l10n.wtmShopStripMoreEyebrow
              : l10n.wtmShopStripKeepEyebrow,
          title: more ? l10n.wtmShopStripMoreTitle : l10n.wtmShopStripKeepTitle,
          actionLabel: l10n.wtmShopViewAll,
          onAction: () => context.push(AppRoute.wtmShopSearch),
        ),
        const SizedBox(height: WtmSpace.s12),
        WtmProductStrip(cards: cards),
      ],
    );
  }

  /// A Giveaway/Offer campaign or a Newsroom read, as the approved layout's
  /// two editorial cards. Both carry exactly ONE action (§9.2, §26.6); the
  /// heading's text action beside it is section navigation, not a second CTA.
  Widget _storyBand(AppLocalizations l10n, DiscoverStory story) {
    final (eyebrow, section, action) = switch (story.type) {
      DiscoverStoryType.giveaway => (
        l10n.wtmDiscoverGiveawayEyebrow,
        l10n.wtmDiscoverGiveawaySection,
        l10n.wtmDiscoverGiveaways,
      ),
      DiscoverStoryType.offer => (
        l10n.wtmDiscoverOfferEyebrow,
        l10n.wtmDiscoverOfferSection,
        l10n.wtmDiscoverOffers,
      ),
      DiscoverStoryType.newsroom => (
        l10n.wtmDiscoverNewsEyebrow,
        l10n.wtmDiscoverNewsSection,
        l10n.wtmDiscoverNewsroom,
      ),
      // The personalized types have no editorial furniture of their own yet;
      // the story's own copy is honest rather than a borrowed heading.
      _ => (story.category, story.title, null),
    };
    final cta = switch (story.type) {
      DiscoverStoryType.giveaway => l10n.wtmStoryCtaViewGiveaway,
      DiscoverStoryType.offer => l10n.wtmStoryCtaViewOffer,
      DiscoverStoryType.newsroom => l10n.wtmStoryCtaReadStory,
      _ => l10n.wtmStoryCtaOpen,
    };
    void open() => widget.onOpenStory(story);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WtmSectionHead(
          eyebrow: eyebrow,
          title: section,
          actionLabel: action,
          onAction: action == null ? null : open,
        ),
        const SizedBox(height: WtmSpace.s12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
          child: story.type == DiscoverStoryType.newsroom
              ? WtmEditorialCard(
                  label: story.category,
                  title: story.title,
                  meta: story.subtitle,
                  imageUrl: story.imageUrl,
                  actionLabel: cta,
                  onTap: open,
                )
              : WtmFeatureCard(
                  label: story.category,
                  title: story.title,
                  meta: story.subtitle,
                  imageUrl: story.imageUrl,
                  actionLabel: cta,
                  onTap: open,
                ),
        ),
      ],
    );
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

  /// Skeleton shaped like the band it is standing in for — a strip of cards,
  /// not a grid — so the first frame does not visibly re-lay-out when the real
  /// products land (§24).
  List<Widget> _skeleton() {
    final width = WtmProductStripMetrics.widthFor(
      MediaQuery.sizeOf(context).width,
    );
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: _pad(context)),
        child: Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: WtmProductStripMetrics.gap),
              LoadingShimmer(
                width: width,
                height: width / DiscoverTokens.productAspect,
                borderRadius: BorderRadius.circular(WtmRadius.tile),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: DiscoverTokens.sectionGap),
    ];
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
