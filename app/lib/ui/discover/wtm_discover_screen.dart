import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/router/routes.dart';
import '../../features/discover/application/discover_providers.dart';
import '../../features/discover/data/discover_story_adapters.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../community/wtm_social_screen.dart';
import '../home/wtm_mood.dart';
import '../widgets/widgets.dart';
import 'wtm_impression.dart';
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
    await ref.read(discoverContentProvider.future);
  }

  /// Builds the rail's stories from live content. Pure composition: the
  /// adapters decide eligibility, [DiscoverRail.compose] orders and caps.
  List<DiscoverStory> _stories(AppLocalizations l10n, DiscoverContent content) {
    final now = DateTime.now();
    return DiscoverRail.compose([
      // Phase 2 adapts the three destination stories from content the app
      // already serves. Today's Edit / Closet Match / New for You need the
      // catalog and ranking from Phase 3; rendering them now would mean a card
      // with nothing behind it, which §6.1 forbids.
      ?DiscoverStoryAdapters.giveaway(
        content.giveaways,
        now: now,
        category: l10n.wtmStoryCatGiveaway,
        title: l10n.wtmStoryGiveawayTitle,
        subtitle: l10n.wtmStoryGiveawayCount,
        liveBadge: l10n.wtmStoryBadgeLive,
      ),
      ?DiscoverStoryAdapters.offer(
        content.offers,
        now: now,
        category: l10n.wtmStoryCatOffer,
        fallbackTitle: l10n.wtmStoryOfferTitle,
      ),
      ?DiscoverStoryAdapters.newsroom(
        content.news,
        now: now,
        category: l10n.wtmStoryCatNewsroom,
        subtitle: l10n.wtmStoryNewsroomSource,
        newBadge: l10n.wtmStoryBadgeNew,
      ),
    ], now: now);
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
        _trackFeedLoaded(content, _stories(l10n, content).length);
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
          padding: const EdgeInsets.only(bottom: wtmNavClearance),
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

  List<Widget> _body(AppLocalizations l10n, DiscoverContent content) {
    // Every source failed. Nothing to partially recover, so this is the error
    // face with a retry rather than a convincing-looking empty state (§24).
    if (content.isTotalFailure) return _error(l10n);

    final stories = _stories(l10n, content);
    final storiesEnabled = ref.watch(
      featureEnabledProvider(FeatureFlags.discoverStories),
    );
    final seen =
        ref.watch(discoverSeenStoriesProvider).asData?.value ?? const {};
    final seenIds = {
      for (final story in stories)
        if (story.isSeenIn(seen)) story.id,
    };

    return [
      if (content.isPartial) ...[
        _Note(message: l10n.wtmDiscoverPartial),
        const SizedBox(height: WtmSpace.s12),
      ],
      if (storiesEnabled && stories.isNotEmpty) ...[
        if (stories.length >= DiscoverRail.minCards)
          WtmStoryRail(
            stories: stories,
            seenIds: seenIds,
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
          )
        else
          // One eligible story is not a rail (§6.1).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
            child: WtmStoryFallbackCard(
              story: stories.first,
              onTap: () => _openViewer(stories, 0),
            ),
          ),
        const SizedBox(height: WtmSpace.s22),
      ],
      // Phase 2 stops at the rail. The "Picked for You" product grid and the
      // contextual modules below it are Phase 3; until then an honest empty
      // state beats a placeholder grid.
      if (stories.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: WtmEmptyState(
            glyph: WtmGlyph.sparkle,
            title: l10n.wtmDiscoverEmptyTitle,
            message: l10n.wtmDiscoverEmptyMessage,
          ),
        ),
    ];
  }

  void _trackFeedLoaded(DiscoverContent content, int storyCount) {
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.discoverFeedLoaded,
          properties: {
            DiscoverAnalyticsProps.storyCount: storyCount,
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

  /// Header + story-card skeletons — never a bare spinner and never a blank
  /// page (§24, CLAUDE.md §4.3).
  List<Widget> _skeleton() {
    final width = MediaQuery.sizeOf(context).width;
    return [
      SizedBox(
        height: WtmStoryCardMetrics.heightFor(width),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
          itemCount: 3,
          separatorBuilder: (_, _) =>
              const SizedBox(width: WtmStoryCardMetrics.gap),
          itemBuilder: (_, _) => LoadingShimmer(
            width: WtmStoryCardMetrics.widthFor(width),
            height: WtmStoryCardMetrics.heightFor(width),
            borderRadius: BorderRadius.circular(WtmRadius.card),
          ),
        ),
      ),
    ];
  }

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

/// `Discover` + the personalization line + Search (§5).
///
/// Saved is not here yet: it opens the Saved screen of §11.3, whose sections
/// are products, looks and offers — none of which exist until Phase 3. A heart
/// that opens an empty room is worse than one that arrives with something in
/// it.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Only a mood the user actually set earns the personalized line; otherwise
    // the honest fallback, never a stale or invented mood (§5).
    final stored = ref.watch(wtmStoredMoodProvider).asData?.value;
    final subtitle = stored == null
        ? l10n.wtmDiscoverSubtitle
        : l10n.wtmDiscoverSubtitleMood(WtmMoodZone.of(stored).label(l10n));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WtmSpace.screenH,
        WtmSpace.s16,
        WtmSpace.screenH,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.wtmDiscoverTitle, style: WtmType.h1),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.micro,
                ),
              ],
            ),
          ),
          WtmIconButton(
            WtmGlyph.search,
            semanticLabel: l10n.wtmDiscoverSearch,
            onTap: () => context.push(AppRoute.wtmSearch),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
      child: Text(message, style: WtmType.micro),
    );
  }
}
