import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/router/routes.dart';
import '../../data/models/product.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/discover/application/discover_providers.dart';
import '../../features/discover/application/product_feed.dart';
import '../../features/discover/application/saved_products.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../features/discover/data/discover_story_adapters.dart';
import '../../features/discover/domain/discover_page.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../features/discover/domain/product_filters.dart';
import '../../features/wardrobe/wardrobe_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../community/wtm_social_screen.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';
import 'wtm_daily_pulse.dart';
import 'wtm_discover_sections.dart';
import 'wtm_feed_modules.dart';
import 'wtm_impression.dart';
import 'wtm_product_card.dart';
import 'wtm_shop_feed.dart';
import 'wtm_shop_filter_sheet.dart';
import 'wtm_story_rail.dart';
import 'wtm_story_viewer.dart';

/// The Discover tab (DISCOVER spec §5).
///
/// Gated on [FeatureFlags.discover]. OFF — which is every build until ops
/// creates the row — this renders the existing community surface exactly as
/// before: the spec's "existing safe fallback, never a blank screen" (§24) and
/// the instant rollback lever (§30).
class WtmDiscoverScreen extends ConsumerWidget {
  const WtmDiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(featureEnabledProvider(FeatureFlags.discover));
    return enabled ? const _Discover() : const WtmSocialScreen();
  }
}

/// Discover's gutter — the prototype's `--pad`, which tightens under its 350px
/// breakpoint.
double _pad(BuildContext context) =>
    DiscoverTokens.padFor(MediaQuery.sizeOf(context).width);

/// Clear space under the last section.
///
/// The same rule every other WTM page now uses — see [wtmBottomClearance] for
/// why the system inset has to be part of it.
double _bottomClearance(BuildContext context) => wtmBottomClearance(context);

class _Discover extends ConsumerStatefulWidget {
  const _Discover();

  @override
  ConsumerState<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends ConsumerState<_Discover> {
  // Owned here, not by the rail, so both survive a rebuild and the return trip
  // from the Story viewer or a destination (§6.5, §23, §33.2).
  final _page = ScrollController();
  final _rail = ScrollController();

  @override
  void initState() {
    super.initState();
    // No scroll listener: Discover does not paginate. The approved layout is a
    // fixed composition that closes on its second curated row, so a second page
    // would have nowhere to go except back into the catalog wall this surface
    // exists to replace. More products live behind View all.
    //
    // One `discover_open` per time the surface is entered, not per rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(analyticsProvider).track(AnalyticsEvents.discoverOpen);
      }
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _rail.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    // Refresh the flags too, so a just-enabled Discover — or a kill-switch —
    // lands without an app restart, matching the community surface.
    ref.invalidate(enabledFeatureFlagsProvider);
    ref.invalidate(discoverContentProvider);
    // The product feed refreshes alongside the stories — pull-to-refresh means
    // fresh prices and availability, not just fresh cards (§33.4) — but ONLY
    // when shopping is on. Refreshing a catalog the user cannot see would be a
    // request for nothing, and on a build with the flag off it would be a
    // request to an endpoint that answers 404 by design.
    final shopping = ref.read(featureEnabledProvider(FeatureFlags.shopping));
    await Future.wait([
      ref.read(discoverContentProvider.future),
      if (shopping) ref.read(productFeedProvider.notifier).refresh(),
    ]);
  }

  // ---------------------------------------------------------------------
  // Stories
  // ---------------------------------------------------------------------

  /// Builds the Discover story POOL from live content — not the rail, which is
  /// its first [DiscoverRail.maxCards] entries.
  ///
  /// Pure composition: the adapters decide eligibility, [DiscoverRail.pool]
  /// orders and de-duplicates. The personalized cards are derived from the
  /// ranked product feed and the user's own wardrobe; the destination cards
  /// from the giveaway, offer and news sources, one per real item. Each adapter
  /// yields nothing when the data behind it is not really there, so a thin pool
  /// is a thin pool rather than a row of convincing-looking empty cards.
  ///
  /// The POOL is what the editorial slots below choose from. Handing them the
  /// capped rail instead would mean a rail full of giveaways could push the
  /// Newsroom card into claiming there is nothing to read, on an account with
  /// thousands of articles.
  List<DiscoverStory> _stories(
    AppLocalizations l10n,
    DiscoverContent content, {
    required List<Product> products,
    required List<WardrobeItem> closet,
    required String? moodLabel,
  }) {
    final now = DateTime.now();
    return DiscoverRail.pool([
      ?DiscoverStoryAdapters.dailyEdit(
        products,
        now: now,
        category: l10n.wtmStoryCatDailyEdit,
        moodLabel: moodLabel,
        title: l10n.wtmStoryDailyEditTitle,
        subtitle: l10n.wtmStoryDailyEditCount,
      ),
      ?DiscoverStoryAdapters.closetMatch(
        closet,
        products: products,
        now: now,
        category: l10n.wtmStoryCatClosetMatch,
        title: l10n.wtmStoryClosetMatchTitle,
        subtitle: l10n.wtmStoryClosetMatchCount,
      ),
      ?DiscoverStoryAdapters.newForYou(
        products,
        now: now,
        category: l10n.wtmStoryCatNewForYou,
        title: l10n.wtmStoryNewForYouTitle,
        subtitle: l10n.wtmStoryNewForYouCount,
      ),
      // The destination sources contribute one card per REAL item, up to their
      // own ceilings, so a rail missing its personalized cards is backfilled
      // with genuine content instead of collapsing to two (§6.1).
      ...DiscoverStoryAdapters.giveaways(
        content.giveaways,
        now: now,
        category: l10n.wtmStoryCatGiveaway,
        title: l10n.wtmStoryGiveawayTitle,
        subtitle: l10n.wtmStoryGiveawayCount,
        liveBadge: l10n.wtmStoryBadgeLive,
      ),
      ...DiscoverStoryAdapters.offers(
        content.offers,
        now: now,
        category: l10n.wtmStoryCatOffer,
        fallbackTitle: l10n.wtmStoryOfferTitle,
      ),
      ...DiscoverStoryAdapters.newsroom(
        content.news,
        now: now,
        category: l10n.wtmStoryCatNewsroom,
        subtitle: l10n.wtmStoryNewsroomSource,
        newBadge: l10n.wtmStoryBadgeNew,
      ),
    ], now: now);
  }

  /// The page as it stands right now, for the analytics listener.
  ///
  /// Composed through the SAME pure function the screen draws from, so what is
  /// reported is what is on screen. It used to re-derive a story count of its
  /// own, which meant the dashboard's idea of the surface and the user's could
  /// drift apart silently — and the mix regression this release fixes is
  /// exactly the kind that hides in that gap.
  ///
  /// The listener fires outside build, so the inputs are read rather than
  /// watched. All of them are already watched in [_body], so they are alive and
  /// this cannot resurrect a disposed provider.
  DiscoverPageLayout _layoutNow(
    AppLocalizations l10n,
    DiscoverContent content,
  ) {
    final mood = ref.read(wtmStoredMoodProvider).asData?.value;
    final products =
        ref.read(productFeedProvider).asData?.value.items ?? const <Product>[];
    final closet =
        ref.read(wardrobeItemsProvider).asData?.value ?? const <WardrobeItem>[];
    return DiscoverPage.compose(
      stories: _stories(
        l10n,
        content,
        products: products,
        closet: closet,
        moodLabel: mood == null ? null : WtmMoodZone.of(mood).label(l10n),
      ),
      products: products,
      closet: closet,
      storiesEnabled: ref.read(
        featureEnabledProvider(FeatureFlags.discoverStories),
      ),
      shoppingEnabled: ref.read(featureEnabledProvider(FeatureFlags.shopping)),
    );
  }

  Map<String, Object> _storyProps(DiscoverStory story, int index) => {
    DiscoverAnalyticsProps.storyType: story.type.wireName,
    DiscoverAnalyticsProps.storyId: story.id,
    DiscoverAnalyticsProps.storyIndex: index,
    if (story.trackingToken != null)
      DiscoverAnalyticsProps.trackingToken: story.trackingToken!,
  };

  Future<void> _openViewer(List<DiscoverStory> stories, int index) async {
    final analytics = ref.read(analyticsProvider);
    analytics.track(
      AnalyticsEvents.discoverStoryOpen,
      properties: _storyProps(stories[index], index),
    );

    final result = await showWtmStoryViewer(
      context,
      stories: stories,
      initialIndex: index,
      onStoryShown: (story) {
        // Seen is recorded only once the story's content is on screen — a
        // failed load must never mark it seen (§6.5).
        ref.read(discoverSeenStoriesProvider.notifier).markSeen(story);
        analytics.track(
          AnalyticsEvents.discoverStorySeen,
          properties: _storyProps(story, stories.indexOf(story)),
        );
      },
      onAction: (story, route) => analytics.track(
        AnalyticsEvents.discoverStoryAction,
        properties: {
          ..._storyProps(story, stories.indexOf(story)),
          DiscoverAnalyticsProps.destination: route,
        },
      ),
    );

    if (!mounted) return;
    final destination = result?.destination;
    if (destination == null) {
      analytics.track(AnalyticsEvents.discoverStoryClose);
      return;
    }
    // The viewer has already popped, so this lands on top of Discover and
    // returns here — with its scroll position intact — on back.
    context.push(destination);
  }

  // ---------------------------------------------------------------------
  // Product actions — unchanged behaviour, moved up from the old feed widget
  // so one place owns them for every row on the page.
  // ---------------------------------------------------------------------

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

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Feed analytics ride on the CONTENT changing, not on build. A build can
    // run many times per load (a flag arriving, a seen-state write, a theme
    // change) and firing from there would both inflate the numbers and modify
    // a provider mid-build, which Riverpod rightly refuses. `ref.listen` fires
    // once per settled load, after the frame — which is also the correct
    // meaning of the event: a pull-to-refresh IS another feed load.
    ref.listen<AsyncValue<DiscoverContent>>(discoverContentProvider, (_, next) {
      final content = next.asData?.value;
      if (content == null) {
        if (next is AsyncError) _trackFeedFailed(null);
        return;
      }
      if (content.isTotalFailure) {
        _trackFeedFailed(content);
      } else {
        _trackFeedLoaded(content, _layoutNow(l10n, content));
      }
    });

    final content = ref.watch(discoverContentProvider);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: WtmColors.gold,
        backgroundColor: WtmColors.panel,
        onRefresh: _refresh,
        child: ListView(
          controller: _page,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: _bottomClearance(context)),
          children: [
            const _Header(),
            const SizedBox(height: WtmSpace.s16),
            ...content.when<List<Widget>>(
              // A refresh keeps the current content on screen instead of
              // flashing skeletons over data the user is already reading
              // (§33.4).
              skipLoadingOnReload: true,
              loading: _skeleton,
              error: (_, _) => _error(l10n),
              data: (data) => _body(l10n, data),
            ),
          ],
        ),
      ),
    );
  }

  /// The approved page, section by section.
  ///
  /// Nothing here decides ORDER or how often a module may appear — that is
  /// [DiscoverPage.compose]'s single job, and it is a pure function so the
  /// rules are tested without a widget. This walks the result and draws it.
  List<Widget> _body(AppLocalizations l10n, DiscoverContent content) {
    // Every source failed. Nothing to partially recover, so this is the error
    // face with a retry rather than a convincing-looking empty state (§24).
    if (content.isTotalFailure) return _error(l10n);

    final storiesEnabled = ref.watch(
      featureEnabledProvider(FeatureFlags.discoverStories),
    );
    final shopping = ref.watch(featureEnabledProvider(FeatureFlags.shopping));
    final feed = shopping
        ? ref.watch(productFeedProvider)
        : const AsyncValue<ProductFeedState>.data(ProductFeedState());
    final filters = ref.watch(productFiltersProvider);
    final state = feed.asData?.value ?? const ProductFeedState();
    // "Still loading" and "confirmed empty" are different facts, and only the
    // second one is an answer. Reading an in-flight wardrobe as `const []` made
    // Complete Your Look pop in a beat after the page settled — and, before the
    // composer reserved its rows, took the closing row's products with it on
    // the way. The composer is told which of the two this is.
    final closetAsync = ref.watch(wardrobeItemsProvider);
    final closet = closetAsync.asData?.value ?? const <WardrobeItem>[];
    final closetResolved = closetAsync.hasValue || closetAsync.hasError;
    // Only a mood the user actually set earns a personalized edit card.
    final storedMood = ref.watch(wtmStoredMoodProvider).asData?.value;
    final moodLabel = storedMood == null
        ? null
        : WtmMoodZone.of(storedMood).label(l10n);

    final stories = _stories(
      l10n,
      content,
      products: state.items,
      closet: closet,
      moodLabel: moodLabel,
    );

    final layout = DiscoverPage.compose(
      stories: stories,
      products: state.items,
      closet: closet,
      closetResolved: closetResolved,
      storiesEnabled: storiesEnabled,
      shoppingEnabled: shopping,
    );

    final hasRows = layout.sections.any((s) => s is ProductRowSection);

    // The rail is the first content section and must not flicker into the
    // one-card fallback while the catalog that feeds three of its six cards is
    // still in flight.
    final railPending =
        storiesEnabled &&
        shopping &&
        feed.isLoading &&
        stories.length < DiscoverRail.minCards;

    return [
      if (content.isPartial) ...[
        _Note(message: l10n.wtmDiscoverPartial),
        const SizedBox(height: WtmSpace.s12),
      ],
      if (state.fromCache) ...[
        const WtmDiscoverOfflineNote(),
        const SizedBox(height: WtmSpace.s12),
      ],
      if (railPending) ...[
        _railSkeleton(),
        const SizedBox(height: DiscoverTokens.sectionGap),
      ] else if (storiesEnabled && layout.fallbackStory != null) ...[
        // One eligible story is not a rail (§6.1) — and the composer only asks
        // for this card when no editorial slot below is already telling the
        // same story.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
          child: WtmStoryFallbackCard(
            story: layout.fallbackStory!,
            onTap: () => _openViewer(stories, 0),
          ),
        ),
        const SizedBox(height: DiscoverTokens.sectionGap),
      ],
      for (final section in layout.sections) ...[
        _section(l10n, section, filters: filters),
        const SizedBox(height: DiscoverTokens.sectionGap),
        // With no products to place, the composer emits no row at all — so the
        // catalog's own skeleton, error or empty face stands exactly where the
        // lead row would have been. Below the editorial modules it would be an
        // explanation the user has to scroll past three cards to find.
        if (!hasRows && section is MoodPulseSection) ...[
          ..._catalogNotice(
            l10n,
            feed,
            state,
            shopping,
            filters.hasAny,
            storiesEmpty: stories.isEmpty,
          ),
          const SizedBox(height: DiscoverTokens.sectionGap),
        ],
      ],
    ];
  }

  Widget _section(
    AppLocalizations l10n,
    DiscoverSection section, {
    required ProductFilters filters,
  }) {
    // Exhaustive over the sealed hierarchy: a new section kind is a compile
    // error here rather than a blank band found in QA (§16).
    return switch (section) {
      StoryRailSection(:final stories) => _SeenAwareRail(
        stories: stories,
        controller: _rail,
        onTap: (story, index) => _openViewer(stories, index),
        wrapCard: (story, index, card) => WtmImpression(
          impressionKey: 'story:${story.id}:${story.contentVersion}',
          onImpression: () => ref
              .read(analyticsProvider)
              .track(
                AnalyticsEvents.discoverStoryImpression,
                properties: _storyProps(story, index),
              ),
          child: card,
        ),
      ),
      MoodPulseSection() => const WtmDailyPulse(),
      ProductRowSection(:final slot, :final products) => WtmDiscoverProductRow(
        slot: slot,
        // The filter affordance rides the lead row's heading, where it is
        // reachable without scrolling past the whole catalog.
        trailing: slot == DiscoverRowSlot.pickedForYou
            ? WtmDiscoverFilterButton(
                label: filters.activeCount == 0
                    ? l10n.wtmShopFilter
                    : l10n.wtmShopFilterCount(filters.activeCount),
                active: filters.activeCount > 0,
                onTap: () => showWtmShopFilterSheet(context, ref),
              )
            : null,
        // BROWSE, not search: results already on screen, keyboard closed. The
        // lead row's heading carries the filter control instead.
        onViewAll: slot == DiscoverRowSlot.pickedForYou
            ? null
            : () => context.push(AppRoute.wtmShopBrowse),
        cards: [for (final product in products) _card(product)],
      ),
      CompleteLookSection(:final look) => Padding(
        padding: EdgeInsets.symmetric(horizontal: _pad(context)),
        child: WtmCompleteLookModule(
          item: look,
          onCta: () {
            ref.read(analyticsProvider).track(AnalyticsEvents.completeLookOpen);
            context.push(AppRoute.wtmCloset);
          },
        ),
      ),
      CampaignSection(:final story) => _editorial(
        l10n,
        newsroom: false,
        story: story,
      ),
      NewsroomSection(:final story) => _editorial(
        l10n,
        newsroom: true,
        story: story,
      ),
    };
  }

  Widget _card(Product product) => WtmImpression(
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
      // The override layer wins, so a save made on Product Details is already
      // reflected when the user comes back — without reloading page 1 and
      // throwing away their scroll position (§33.2).
      product: product.copyWith(saved: watchSaved(ref, product)),
      onToggleSave: () => _toggleSave(product),
      // `push`, not `go`: Discover stays alive underneath with its scroll
      // offset and every loaded page intact, and back returns exactly there.
      onTap: () => context.push(
        '${AppRoute.wtmProductPath(product.id)}&from=feed_grid',
        extra: product,
      ),
      onTryOn: () => _tryOn(product),
    ),
  );

  /// A Giveaway/Offer campaign or a Newsroom read, as the approved layout's two
  /// editorial cards. Both carry exactly ONE action (§9.2, §26.6); the
  /// heading's text action beside it is section navigation, not a second CTA.
  ///
  /// [story] is null when nothing is live. The card still renders — the slot
  /// holds its place so the page keeps a fixed rhythm — but it says plainly
  /// that there is nothing and offers the hub instead. It never dresses an
  /// empty slot up as a campaign.
  Widget _editorial(
    AppLocalizations l10n, {
    required bool newsroom,
    required DiscoverStory? story,
  }) {
    final (eyebrow, section, action) = switch (story?.type) {
      DiscoverStoryType.offer => (
        l10n.wtmDiscoverOfferEyebrow,
        l10n.wtmDiscoverOfferSection,
        l10n.wtmDiscoverOffers,
      ),
      DiscoverStoryType.newsroom || null when newsroom => (
        l10n.wtmDiscoverNewsEyebrow,
        l10n.wtmDiscoverNewsSection,
        l10n.wtmDiscoverNewsroom,
      ),
      _ => (
        l10n.wtmDiscoverGiveawayEyebrow,
        l10n.wtmDiscoverGiveawaySection,
        l10n.wtmDiscoverGiveaways,
      ),
    };

    // The card and the heading are two different invitations and must not share
    // a destination.
    //
    // The CARD is this story, so it opens this story. The HEADING is the
    // section's own link — "Newsroom", "Giveaways" — and always opens the hub.
    // They used to share one callback built from the story's route, so tapping
    // "Newsroom" landed on a single article; the newsroom then looked like a
    // newsroom containing exactly one story, which is how it was reported.
    // An empty slot has no story, so both fall back to the hub.
    final hub = newsroom ? AppRoute.wtmNewsroom : AppRoute.wtmGiveaways;
    void openHub() => context.push(hub);
    void openStory() => context.push(story?.destination.route ?? hub);

    final label =
        story?.category ??
        (newsroom ? l10n.wtmStoryCatNewsroom : l10n.wtmStoryCatGiveaway);
    final title =
        story?.title ??
        (newsroom
            ? l10n.wtmDiscoverNewsEmptyTitle
            : l10n.wtmDiscoverGiveawayEmptyTitle);
    final meta =
        story?.subtitle ??
        (newsroom
            ? l10n.wtmDiscoverNewsEmptyMeta
            : l10n.wtmDiscoverGiveawayEmptyMeta);
    final cta = switch (story?.type) {
      DiscoverStoryType.giveaway => l10n.wtmStoryCtaViewGiveaway,
      DiscoverStoryType.offer => l10n.wtmStoryCtaViewOffer,
      DiscoverStoryType.newsroom => l10n.wtmStoryCtaReadStory,
      _ =>
        newsroom
            ? l10n.wtmDiscoverNewsEmptyCta
            : l10n.wtmDiscoverGiveawayEmptyCta,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WtmSectionHead(
          eyebrow: eyebrow,
          title: section,
          actionLabel: action,
          onAction: openHub,
        ),
        const SizedBox(height: WtmSpace.s12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pad(context)),
          child: newsroom
              ? WtmEditorialCard(
                  label: label,
                  title: title,
                  meta: meta,
                  imageUrl: story?.imageUrl,
                  actionLabel: cta,
                  onTap: openStory,
                )
              : WtmFeatureCard(
                  label: label,
                  title: title,
                  meta: meta,
                  imageUrl: story?.imageUrl,
                  actionLabel: cta,
                  onTap: openStory,
                ),
        ),
      ],
    );
  }

  /// What stands in for the lead product row when there is no row to draw: the
  /// catalog's skeleton, its error face, or one of the three empty states.
  ///
  /// Never a full-screen spinner over content the user is already reading, and
  /// never a bare blank where a section was promised (§23, §24).
  List<Widget> _catalogNotice(
    AppLocalizations l10n,
    AsyncValue<ProductFeedState> feed,
    ProductFeedState state,
    bool shopping,
    bool filtered, {
    required bool storiesEmpty,
  }) {
    if (!shopping) {
      // No catalog to explain. Discover is still a surface — but with the
      // content sources empty too, the page would be a header and a mood chip,
      // so it says so plainly rather than looking broken (§24).
      if (!storiesEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: WtmEmptyState(
            glyph: WtmGlyph.sparkle,
            title: l10n.wtmDiscoverEmptyTitle,
            message: l10n.wtmDiscoverEmptyMessage,
          ),
        ),
      ];
    }
    if (feed.isLoading) return const [WtmDiscoverRowSkeleton()];
    if (feed.hasError) {
      return [
        WtmErrorState(
          title: l10n.wtmDiscoverErrorTitle,
          message: l10n.errorGenericTitle,
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(productFeedProvider),
        ),
      ];
    }
    return [
      WtmDiscoverCatalogEmpty(
        regionEmpty: state.regionEmpty,
        filtered: filtered,
        onResetFilters: () => ref.read(productFiltersProvider.notifier).reset(),
      ),
    ];
  }

  void _trackFeedLoaded(DiscoverContent content, DiscoverPageLayout layout) {
    final rail = layout.sections.whereType<StoryRailSection>().firstOrNull;
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.discoverFeedLoaded,
          properties: {
            // The RAIL's length — what is on screen — not the pool's, which is
            // larger and would report cards nobody can see.
            DiscoverAnalyticsProps.storyCount:
                rail?.stories.length ?? (layout.fallbackStory == null ? 0 : 1),
            // The whole page's depth and mix. A thin or lopsided Discover is a
            // content problem, and it is only fixable if it is visible.
            DiscoverAnalyticsProps.cardCount: layout.cardCount,
            DiscoverAnalyticsProps.cardShortfall: layout.isThin,
            DiscoverAnalyticsProps.giveawayCardCount: layout.cardsOfType(
              DiscoverStoryType.giveaway,
            ),
            DiscoverAnalyticsProps.newsCardCount: layout.cardsOfType(
              DiscoverStoryType.newsroom,
            ),
            DiscoverAnalyticsProps.failedSources: content.failedSources,
            DiscoverAnalyticsProps.partial: content.isPartial,
          },
        );
  }

  /// [content] is null when the provider itself errored rather than reporting
  /// per-source failures — both are the same thing to a dashboard.
  void _trackFeedFailed(DiscoverContent? content) {
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.discoverFeedFailed,
          properties: {
            DiscoverAnalyticsProps.failedSources:
                content?.failedSources ?? content?.totalSources ?? 3,
          },
        );
  }

  Widget _railSkeleton() {
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: WtmStoryCardMetrics.heightFor(width),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _pad(context)),
        itemCount: 3,
        separatorBuilder: (_, _) =>
            const SizedBox(width: WtmStoryCardMetrics.gap),
        itemBuilder: (_, _) => LoadingShimmer(
          width: WtmStoryCardMetrics.widthFor(width),
          height: WtmStoryCardMetrics.heightFor(width),
          borderRadius: BorderRadius.circular(WtmRadius.card),
        ),
      ),
    );
  }

  /// Header + story-card skeletons — never a bare spinner and never a blank
  /// page (§24, CLAUDE.md §4.3).
  List<Widget> _skeleton() => [_railSkeleton()];

  List<Widget> _error(AppLocalizations l10n) => [
    Padding(
      padding: const EdgeInsets.only(top: 40),
      child: WtmErrorState(
        title: l10n.wtmDiscoverErrorTitle,
        message: l10n.errorGenericTitle,
        retryLabel: l10n.commonRetry,
        onRetry: () => ref.invalidate(discoverContentProvider),
      ),
    ),
  ];
}

/// `Discover` + the personalization line + Saved + Search (§5).
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final pad = DiscoverTokens.padFor(width);
    // Only a mood the user actually set earns the personalized line; otherwise
    // the honest fallback, never a stale or invented mood (§5).
    final stored = ref.watch(wtmStoredMoodProvider).asData?.value;

    return Padding(
      // `header { padding: 14px var(--pad) 12px }`
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.wtmDiscoverTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiscoverTokens.title(width),
                ),
                const SizedBox(height: 9), // .subtitle margin-top
                _Subtitle(mood: stored),
              ],
            ),
          ),
          const SizedBox(width: 14), // header gap
          // Saved arrives with the catalog it holds — a heart that opened an
          // empty room would have been worse than one that waited (§11.3).
          if (ref.watch(featureEnabledProvider(FeatureFlags.shopping))) ...[
            WtmDiscoverIconButton(
              glyph: WtmGlyph.heart,
              semanticLabel: l10n.wtmShopSavedTitle,
              onTap: () => context.push(AppRoute.wtmSaved),
            ),
            const SizedBox(width: 10), // .header-actions gap
          ],
          WtmDiscoverIconButton(
            glyph: WtmGlyph.search,
            semanticLabel: l10n.wtmDiscoverSearch,
            onTap: () => context.push(AppRoute.wtmShopSearch),
          ),
        ],
      ),
    );
  }
}

/// The Story rail, with the seen-state watch scoped to it.
///
/// Marking a story seen used to rebuild the WHOLE Discover page: the screen
/// watched `discoverSeenStoriesProvider` in its own build, so every return from
/// the viewer re-ran the story adapters, re-composed the layout and rebuilt
/// every section — to change one card's border. The watch belongs where the
/// only thing that reads it is.
class _SeenAwareRail extends ConsumerWidget {
  const _SeenAwareRail({
    required this.stories,
    required this.controller,
    required this.onTap,
    required this.wrapCard,
  });

  final List<DiscoverStory> stories;
  final ScrollController controller;
  final void Function(DiscoverStory story, int index) onTap;
  final Widget Function(DiscoverStory story, int index, Widget card) wrapCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen =
        ref.watch(discoverSeenStoriesProvider).asData?.value ?? const {};
    return WtmStoryRail(
      stories: stories,
      seenIds: {
        for (final story in stories)
          if (story.isSeenIn(seen)) story.id,
      },
      controller: controller,
      onTap: onTap,
      wrapCard: wrapCard,
    );
  }
}

/// `.subtitle` — with the mood word in gold (`.subtitle strong`).
///
/// Built as a rich span rather than two Texts so the sentence wraps and
/// translates as one string; the placeholder is what gets recoloured.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.mood});

  final double? mood;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (mood == null) {
      return Text(
        l10n.wtmDiscoverSubtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: DiscoverTokens.subtitle,
      );
    }

    final label = WtmMoodZone.of(mood!).label(l10n);
    final sentence = l10n.wtmDiscoverSubtitleFresh(label);
    final at = sentence.indexOf(label);
    // If a translation drops or reorders the placeholder, fall back to the
    // plain sentence rather than slicing at a wrong index.
    if (at < 0) {
      return Text(
        sentence,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: DiscoverTokens.subtitle,
      );
    }

    return Text.rich(
      TextSpan(
        style: DiscoverTokens.subtitle,
        children: [
          TextSpan(text: sentence.substring(0, at)),
          TextSpan(text: label, style: DiscoverTokens.subtitleStrong),
          TextSpan(text: sentence.substring(at + label.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A quiet, non-blocking status line — used when part of Discover failed but
/// the rest rendered. Never red: partial content is not an error (§25).
class _Note extends StatelessWidget {
  const _Note({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _pad(context)),
      child: Text(message, style: WtmType.micro),
    );
  }
}
