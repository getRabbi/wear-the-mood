import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../data/models/style_memory.dart';
import '../../data/repositories/style_memory_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../widgets/widgets.dart';

/// "What WTM knows about my style" (RETENTION spec §12.2).
///
/// The screen exists to make the profile ANSWERABLE. Three obligations shape
/// every widget on it:
///
///   * **Nothing is stated more strongly than the evidence supports.** A
///     preference below [PreferenceItem.stateThreshold] is labelled a hunch,
///     not a fact (§12.3).
///   * **Anything can be removed**, one entry at a time, without wiping the
///     rest.
///   * **Personalization can be switched off without deletion**, and deletion
///     is available separately. A user who wants us to stop using their taste
///     should not have to destroy it to say so.
class WtmStyleMemoryScreen extends ConsumerStatefulWidget {
  const WtmStyleMemoryScreen({super.key});

  @override
  ConsumerState<WtmStyleMemoryScreen> createState() =>
      _WtmStyleMemoryScreenState();
}

class _WtmStyleMemoryScreenState extends ConsumerState<WtmStyleMemoryScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Fired once per open, after the first frame so it cannot interleave with
    // the build that is still running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.styleMemorySummaryViewed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(styleMemoryProvider);

    return WtmPage(
      title: l10n.styleMemoryTitle,
      eyebrow: l10n.styleMemorySubtitle,
      children: [
        profile.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: WtmSpace.s22),
            child: LoadingShimmer(width: double.infinity, height: 220),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.only(top: WtmSpace.s22),
            child: WtmErrorState(
              title: l10n.errorGenericTitle,
              message: l10n.styleMemoryError,
              retryLabel: l10n.commonRetry,
              onRetry: () => ref.invalidate(styleMemoryProvider),
            ),
          ),
          data: (data) => _Content(
            profile: data,
            busy: _busy,
            onRemove: (facet, value) => _remove(facet, value),
            onPersonalization: _setPersonalization,
            onReset: _reset,
          ),
        ),
      ],
    );
  }

  Future<void> _guard(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.styleMemoryError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String facet, String value) => _guard(() async {
    await ref
        .read(styleMemoryRepositoryProvider)
        .correct(facet: facet, value: value, remove: true);
    ref.invalidate(styleMemoryProvider);
    await ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.styleMemoryPreferenceEdited,
          properties: {'facet': facet, 'removed': true},
        );
  });

  Future<void> _setPersonalization(bool enabled) => _guard(() async {
    await ref
        .read(styleMemoryRepositoryProvider)
        .setPersonalization(enabled: enabled);
    ref.invalidate(styleMemoryProvider);
  });

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await wtmConfirmDialog(
      context,
      title: l10n.styleMemoryReset,
      message: l10n.styleMemoryResetConfirm,
      confirmLabel: l10n.styleMemoryReset,
      danger: true,
    );
    if (!confirmed || !mounted) return;
    await _guard(() async {
      await ref.read(styleMemoryRepositoryProvider).reset();
      ref.invalidate(styleMemoryProvider);
      await ref.read(analyticsProvider).track(AnalyticsEvents.styleMemoryReset);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.styleMemoryResetDone)));
      }
    });
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.profile,
    required this.busy,
    required this.onRemove,
    required this.onPersonalization,
    required this.onReset,
  });

  final StyleMemoryProfile profile;
  final bool busy;
  final void Function(String facet, String value) onRemove;
  final void Function(bool enabled) onPersonalization;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final populated = profile.facets
        .where(
          (f) => f.items.isNotEmpty && _facetLabel(l10n, f.facet).isNotEmpty,
        )
        .toList();

    if (profile.isEmpty && populated.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: WtmSpace.s22),
        child: WtmEmptyState(
          glyph: WtmGlyph.sparkle,
          title: l10n.styleMemoryEmptyTitle,
          message: l10n.styleMemoryEmptyMessage,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile.preferenceSummary != null) ...[
          _SummaryCard(
            summary: profile.preferenceSummary!,
            confidence: profile.confidence,
          ),
          const SizedBox(height: WtmSpace.s14),
        ],
        for (final facet in populated) ...[
          _FacetSection(
            label: _facetLabel(l10n, facet.facet),
            items: facet.items,
            busy: busy,
            onRemove: (value) => onRemove(facet.facet, value),
          ),
          const SizedBox(height: WtmSpace.s14),
        ],
        _PersonalizationRow(
          enabled: profile.personalizationEnabled,
          busy: busy,
          onChanged: onPersonalization,
        ),
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.styleMemoryReset,
          onPressed: busy ? null : onReset,
        ),
        const SizedBox(height: WtmSpace.s22),
      ],
    );
  }
}

/// Facet key -> its localized section header. Lives here, next to the widget
/// that renders it, because it is display text — the model deals only in the
/// key the API expects (CLAUDE.md §4.3).
String _facetLabel(AppLocalizations l10n, String facet) => switch (facet) {
  'preferred_colors' => l10n.styleMemoryFacetColors,
  'preferred_silhouettes' => l10n.styleMemoryFacetSilhouettes,
  'preferred_aesthetics' => l10n.styleMemoryFacetAesthetics,
  'preferred_occasions' => l10n.styleMemoryFacetOccasions,
  'preferred_moods' => l10n.styleMemoryFacetMoods,
  'avoided_colors' => l10n.styleMemoryFacetAvoidedColors,
  'avoided_silhouettes' => l10n.styleMemoryFacetAvoidedSilhouettes,
  // A facet the server added and this build does not know about yet. Skipped
  // by the caller rather than shown with a raw key.
  _ => '',
};

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.confidence});

  final String summary;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Three bands rather than a percentage. A number invites the user to argue
    // with our arithmetic; a word describes how much we have actually seen.
    final label = switch (confidence) {
      < 0.34 => l10n.styleMemoryConfidenceLow,
      < 0.67 => l10n.styleMemoryConfidenceBuilding,
      _ => l10n.styleMemoryConfidenceStrong,
    };
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s16),
      decoration: BoxDecoration(
        color: WtmColors.chipOnBg,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.chipOnBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: WtmType.label.copyWith(color: WtmColors.gold)),
          const SizedBox(height: WtmSpace.s6),
          Text(summary, style: WtmType.body),
        ],
      ),
    );
  }
}

class _FacetSection extends StatelessWidget {
  const _FacetSection({
    required this.label,
    required this.items,
    required this.busy,
    required this.onRemove,
  });

  final String label;
  final List<PreferenceItem> items;
  final bool busy;
  final void Function(String value) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: WtmType.label.copyWith(color: WtmColors.muted)),
        const SizedBox(height: WtmSpace.s8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: WtmSpace.s6),
            child: _PreferenceRow(
              item: item,
              busy: busy,
              onRemove: () => onRemove(item.value),
            ),
          ),
      ],
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.item,
    required this.busy,
    required this.onRemove,
  });

  final PreferenceItem item;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
        horizontal: WtmSpace.s14,
        vertical: WtmSpace.s8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.value, style: WtmType.body),
                // The honesty label. A stated preference is the user's own
                // word; anything we merely noticed, and noticed weakly, says
                // so rather than posing as a finding.
                if (item.isStated)
                  Text(
                    l10n.styleMemoryYouSaid,
                    style: WtmType.label.copyWith(color: WtmColors.gold),
                  )
                else if (!item.isConfident)
                  Text(
                    l10n.styleMemoryHunch,
                    style: WtmType.label.copyWith(color: WtmColors.muted),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRemove,
            child: Text(
              l10n.styleMemoryRemove,
              style: WtmType.label.copyWith(color: WtmColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalizationRow extends StatelessWidget {
  const _PersonalizationRow({
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final void Function(bool enabled) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WtmRow(
          glyph: WtmGlyph.sliders,
          title: l10n.styleMemoryPersonalization,
          trailing: Switch(
            value: enabled,
            onChanged: busy ? null : onChanged,
            activeTrackColor: WtmColors.gold,
          ),
        ),
        if (!enabled) ...[
          const SizedBox(height: WtmSpace.s6),
          Text(l10n.styleMemoryPersonalizationOff, style: WtmType.sub),
        ],
      ],
    );
  }
}
