import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/planner.dart';
import '../../data/repositories/credits_repository.dart';
import '../../data/repositories/planner_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Mood Planner v2 (RETENTION spec §14).
///
/// The cheap half of the product, and deliberately so: picking a mood costs
/// nothing, calls no provider and consumes no credit. That is what makes it a
/// reason to open WTM on a day the user has no intention of spending.
///
/// Rendering stays a separate, explicit act. The direction is shown first and
/// **See it on me** — labelled with its real credit cost — is the only path
/// from here to a paid render. Nothing on this screen renders automatically.
class WtmMoodPlannerScreen extends ConsumerStatefulWidget {
  const WtmMoodPlannerScreen({super.key});

  @override
  ConsumerState<WtmMoodPlannerScreen> createState() =>
      _WtmMoodPlannerScreenState();
}

class _WtmMoodPlannerScreenState extends ConsumerState<WtmMoodPlannerScreen> {
  PlannerMood? _mood;
  PlannerOccasion? _occasion;
  MoodPlan? _plan;
  bool _busy = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The cost shown on "See it on me" comes from the server's own price list,
    // never from a constant here — the number the user reads and the number
    // they are charged are then the same number by construction.
    final stdCost = ref.watch(creditsProvider).asData?.value.stdCost ?? 1;

    return WtmPage(
      title: l10n.moodPlannerTitle,
      eyebrow: l10n.moodPlannerSubtitle,
      children: [
        _ChipRow(
          labels: {
            PlannerMood.calm: l10n.moodCalm,
            PlannerMood.confident: l10n.moodConfident,
            PlannerMood.bold: l10n.moodBold,
            PlannerMood.rebel: l10n.moodRebel,
          },
          selected: _mood,
          onSelect: (value) => setState(() {
            _mood = value;
            // The old direction was for a different mood. Keeping it on screen
            // under a new chip would show the user an answer to a question
            // they just changed.
            _plan = null;
            _failed = false;
          }),
        ),
        const SizedBox(height: WtmSpace.s18),
        Text(
          l10n.moodPlannerOccasion,
          style: WtmType.label.copyWith(color: WtmColors.muted),
        ),
        const SizedBox(height: WtmSpace.s8),
        _ChipRow(
          labels: {
            PlannerOccasion.everyday: l10n.occasionEveryday,
            PlannerOccasion.work: l10n.occasionWork,
            PlannerOccasion.date: l10n.occasionDate,
            PlannerOccasion.brunch: l10n.occasionBrunch,
            PlannerOccasion.wedding: l10n.occasionWedding,
            PlannerOccasion.nightOut: l10n.occasionNightOut,
          },
          selected: _occasion,
          // Tapping the selected occasion clears it: "no occasion" is a valid
          // answer and must stay reachable once one has been chosen.
          onSelect: (value) => setState(() {
            _occasion = _occasion == value ? null : value;
            _plan = null;
            _failed = false;
          }),
        ),
        const SizedBox(height: WtmSpace.s18),
        GradientCta(
          label: l10n.moodPlannerCreate,
          onPressed: _mood == null || _busy ? null : _create,
        ),
        const SizedBox(height: WtmSpace.s18),
        if (_busy)
          const LoadingShimmer(width: double.infinity, height: 160)
        else if (_failed)
          WtmErrorState(
            title: l10n.errorGenericTitle,
            message: l10n.moodPlannerError,
            retryLabel: l10n.commonRetry,
            onRetry: _create,
          )
        else if (_plan != null)
          _DirectionCard(plan: _plan!, renderCost: stdCost, onRender: _render),
        const SizedBox(height: WtmSpace.s22),
      ],
    );
  }

  Future<void> _create() async {
    final mood = _mood;
    if (mood == null || _busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final plan = await ref
          .read(plannerRepositoryProvider)
          .createMoodPlan(mood: mood, occasion: _occasion);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _failed = plan == null;
      });
      if (plan != null) {
        final analytics = ref.read(analyticsProvider);
        await analytics.track(
          AnalyticsEvents.moodPlanCreated,
          properties: {
            'mood': mood.wire,
            if (_occasion != null) 'occasion': _occasion!.wire,
            // Whether the direction could name real pieces. A generic plan is
            // an honest outcome for a thin closet, and worth distinguishing.
            'generic': plan.generic,
          },
        );
        await analytics.track(
          AnalyticsEvents.moodSelected,
          properties: {'mood': mood.wire},
        );
        if (_occasion != null) {
          await analytics.track(
            AnalyticsEvents.occasionSelected,
            properties: {'occasion': _occasion!.wire},
          );
        }
        // The latest-plan provider backs Home's "Continue your style"; it has
        // to hear about a plan made while Home was still in the widget tree.
        ref.invalidate(latestMoodPlanProvider);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The ONE path from a free plan to a paid render, and only ever on a tap.
  void _render() => context.push(AppRoute.wtmMirror);
}

/// A single-select chip strip. Generic over the enum so mood and occasion do
/// not need two near-identical widgets.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final Map<T, String> labels;
  final T? selected;
  final void Function(T value) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: WtmSpace.s8,
      runSpacing: WtmSpace.s8,
      children: [
        for (final entry in labels.entries)
          WtmChip(
            label: entry.value,
            on: selected == entry.key,
            onTap: () => onSelect(entry.key),
          ),
      ],
    );
  }
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.plan,
    required this.renderCost,
    required this.onRender,
  });

  final MoodPlan plan;
  final int renderCost;
  final VoidCallback onRender;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s16),
      decoration: BoxDecoration(
        color: WtmColors.panel,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(plan.headline, style: WtmType.h2.copyWith(fontSize: 19)),
          const SizedBox(height: WtmSpace.s10),
          for (final line in plan.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: WtmSpace.s6),
              child: Text(line, style: WtmType.sub),
            ),
          const SizedBox(height: WtmSpace.s14),
          GhostButton(label: l10n.moodPlannerSeeItOnMe, onPressed: onRender),
          const SizedBox(height: WtmSpace.s6),
          // The cost is stated BEFORE the tap, not discovered after it.
          Text(
            l10n.moodPlannerRenderNote(renderCost),
            textAlign: TextAlign.center,
            style: WtmType.label.copyWith(color: WtmColors.muted),
          ),
        ],
      ),
    );
  }
}
