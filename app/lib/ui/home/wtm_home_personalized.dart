import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../core/router/routes.dart';
import '../../data/repositories/planner_repository.dart';
import '../../data/repositories/style_memory_repository.dart';
import '../../features/collections/local_collections.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Personalized Home v2 (RETENTION spec §13, Phase 5).
///
/// **What this is not:** a Home rewrite. Nothing existing is removed, reordered
/// or restyled. This is one additive block that renders between Today's Look
/// and the Discover preview, and renders NOTHING AT ALL when
/// `feature_personalized_home_v2` is off — which is the contract the flag
/// exists to keep (§13.3).
///
/// **Maturity-aware, not two screens.** A new user has no plan, no event and no
/// style memory, so the modules that describe those simply have nothing to draw
/// and are absent. What they get instead is one clear next action. A mature
/// user's Home fills in as their history accumulates. There is no branch on
/// "is this user new" — the presence of their own data decides, which means
/// the transition happens continuously instead of at some arbitrary threshold.
///
/// Every module fails quiet: a module whose data is loading or errored is
/// simply not drawn. A retention shelf is not worth an error state on the first
/// screen of the app.
class WtmHomePersonalized extends ConsumerWidget {
  const WtmHomePersonalized({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featureEnabledProvider(FeatureFlags.personalizedHomeV2))) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);

    final plan = ref.watch(latestMoodPlanProvider).asData?.value;
    final nextEvent = ref.watch(upcomingEventsProvider).asData?.value.nextEvent;
    final memory = ref.watch(styleMemoryProvider).asData?.value;
    final looks = ref.watch(savedLookRecordsProvider);

    // The summary is only surfaced once WTM can say something it actually
    // believes. A hedge on Home would be worse than silence (§12.3).
    final summary = (memory != null && memory.confidence >= 0.35)
        ? memory.preferenceSummary
        : null;

    final modules = <Widget>[
      if (plan != null)
        _Module(
          eyebrow: l10n.homeContinueStyle,
          title: plan.headline,
          body: plan.lines.isEmpty ? null : plan.lines.first,
          onTap: () => context.push(AppRoute.wtmMoodPlanner),
        )
      else
        // The new-user state: ONE clear next action, and a free one.
        _Module(
          eyebrow: l10n.homeTodaysMood,
          title: l10n.moodPlannerTitle,
          body: l10n.moodPlannerSubtitle,
          onTap: () => context.push(AppRoute.wtmMoodPlanner),
        ),
      if (nextEvent != null)
        _Module(
          eyebrow: l10n.homeUpcomingEvent,
          title: nextEvent.name,
          body: switch (nextEvent) {
            _ when nextEvent.daysAway == 0 => l10n.eventToday,
            _ when nextEvent.daysAway == 1 => l10n.eventTomorrow,
            _ => l10n.eventInDays(nextEvent.daysAway),
          },
          onTap: () {
            ref.read(analyticsProvider).track(AnalyticsEvents.eventRevisited);
            context.push(AppRoute.wtmEvents);
          },
        ),
      if (summary != null)
        _Module(
          eyebrow: l10n.homeBasedOnStyle,
          title: summary,
          onTap: () => context.push(AppRoute.wtmStyleMemory),
        ),
      if (looks.isNotEmpty) _WearAgainRail(looks: looks),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final module in modules) ...[
          const SizedBox(height: WtmSpace.s16),
          module,
        ],
      ],
    );
  }
}

class _Module extends StatelessWidget {
  const _Module({
    required this.eyebrow,
    required this.title,
    this.body,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String? body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$eyebrow: $title',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          child: Container(
            // 48dp floor even when the title is one short word (§41).
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.all(WtmSpace.s14),
            decoration: BoxDecoration(
              color: WtmColors.panel,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                EyebrowLabel(eyebrow),
                const SizedBox(height: WtmSpace.s6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.h2.copyWith(fontSize: 17),
                ),
                if (body != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WtmType.sub,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Wear again" — the looks the user already kept, which is the cheapest
/// possible reason to re-open the app: no render, no network, no credit.
class _WearAgainRail extends ConsumerWidget {
  const _WearAgainRail({required this.looks});

  final List<SavedLook> looks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Newest first, and bounded: a rail is a prompt, not the whole archive.
    final recent = looks.reversed.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowLabel(l10n.homeWearAgain),
        const SizedBox(height: WtmSpace.s10),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: WtmSpace.s8),
            itemBuilder: (context, index) {
              final look = recent[index];
              return Semantics(
                button: true,
                label: l10n.homeWearAgain,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: () {
                      ref
                          .read(analyticsProvider)
                          .track(AnalyticsEvents.savedLookRevisited);
                      context.push(AppRoute.wtmProfileSaved);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(WtmRadius.card),
                      child: CachedNetworkImage(
                        imageUrl: look.imageUrl,
                        width: 92,
                        height: 132,
                        fit: BoxFit.cover,
                        // A saved look whose durable URL has gone is a gap in a
                        // rail, never a broken Home.
                        errorWidget: (_, _, _) => Container(
                          width: 92,
                          height: 132,
                          color: WtmColors.panel,
                        ),
                        placeholder: (_, _) => Container(
                          width: 92,
                          height: 132,
                          color: WtmColors.panel,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
