import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/flags/feature_flags.dart';
import '../../data/models/style_memory.dart';
import '../../data/repositories/style_memory_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Keep it / Not me on a finished render (RETENTION spec §18).
///
/// Two things this row is careful about.
///
/// **It is not a refund control.** A render that failed, lost a garment, or was
/// rejected by the fidelity gate was refunded by the worker before this screen
/// ever appeared. What the user is judging here is a render that WORKED, so
/// "Not me" collects a reason and changes nothing about their credits — which
/// the sheet says out loud rather than leaving the user to wonder.
///
/// **It is additive.** Save Look, Adjust, Retry and Share are untouched; this
/// sits above them, and disappears entirely when the flag is off.
class WtmResultFeedback extends ConsumerStatefulWidget {
  const WtmResultFeedback({super.key, required this.resultId});

  /// The persisted result row. Null while a job has not produced one yet — the
  /// row hides itself rather than offering a verdict it cannot record.
  final String? resultId;

  @override
  ConsumerState<WtmResultFeedback> createState() => _WtmResultFeedbackState();
}

class _WtmResultFeedbackState extends ConsumerState<WtmResultFeedback> {
  bool _busy = false;
  String? _outcome;
  String? _learned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = ref.watch(
      featureEnabledProvider(FeatureFlags.styleMemoryFeedback),
    );
    final resultId = widget.resultId;
    if (!enabled || resultId == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_learned != null) ...[
          _LearnedCard(line: _learned!),
          const SizedBox(height: WtmSpace.s10),
        ],
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: _outcome == 'kept' ? l10n.resultKept : l10n.resultKeepIt,
                onPressed: _busy || _outcome == 'kept'
                    ? null
                    : () => _submit(resultId, kept: true),
              ),
            ),
            const SizedBox(width: WtmSpace.s10),
            Expanded(
              child: GhostButton(
                label: l10n.resultNotMe,
                onPressed: _busy ? null : () => _reject(resultId),
              ),
            ),
          ],
        ),
        const SizedBox(height: WtmSpace.s10),
      ],
    );
  }

  Future<void> _submit(
    String resultId, {
    required bool kept,
    RejectionReason? reason,
  }) async {
    setState(() => _busy = true);
    final analytics = ref.read(analyticsProvider);
    try {
      final result = await ref
          .read(styleMemoryRepositoryProvider)
          .submitFeedback(resultId: resultId, kept: kept, reason: reason);
      if (!mounted) return;
      setState(() {
        _outcome = kept ? 'kept' : 'rejected';
        // Only shown when the server says the summary actually moved. A
        // "we learned something" that follows every single tap is noise, and
        // one that follows a tap that changed nothing is a lie.
        _learned = result?.learned;
      });
      await analytics.track(
        kept ? AnalyticsEvents.tryonKept : AnalyticsEvents.tryonRejected,
        properties: {
          'result_id': resultId,
          if (reason != null) 'reason': reason.wire,
        },
      );
      if (reason != null) {
        await analytics.track(
          AnalyticsEvents.tryonRejectionReason,
          properties: {'reason': reason.wire},
        );
      }
    } catch (_) {
      // Feedback is a courtesy, never a blocker: a failed record must not
      // interrupt someone who is looking at their render.
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.commonRetry)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(String resultId) async {
    final reason = await showModalBottomSheet<RejectionReason>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ReasonSheet(),
    );
    if (reason == null || !mounted) return;
    await _submit(resultId, kept: false, reason: reason);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.resultFeedbackThanks)));
  }
}

/// The structured "what didn't work?" sheet (§18).
///
/// The order is deliberate: render-quality complaints come first because they
/// are the ones a user reaches for when something is visibly broken, and they
/// are also the ones the server refuses to learn taste from.
class _ReasonSheet extends StatelessWidget {
  const _ReasonSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reasons = <(RejectionReason, String)>[
      (RejectionReason.identityIssue, l10n.resultReasonIdentity),
      (RejectionReason.garmentIssue, l10n.resultReasonGarment),
      (RejectionReason.bodyProportionIssue, l10n.resultReasonBody),
      (RejectionReason.notMyStyle, l10n.resultReasonStyle),
      (RejectionReason.colorIssue, l10n.resultReasonColor),
      (RejectionReason.occasionMismatch, l10n.resultReasonOccasion),
      (RejectionReason.other, l10n.resultReasonOther),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(WtmSpace.screenH),
        padding: const EdgeInsets.all(WtmSpace.s18),
        // Seven reasons plus a title and a subtitle do not fit a 320x640dp
        // phone, and at 2.0x text they do not fit anything. Capped at 80% of
        // the viewport and scrolled inside that cap, so the sheet is always
        // shorter than the screen and every reason is always reachable —
        // instead of the last three being clipped off the bottom behind an
        // overflow stripe (§41 dynamic type).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: BoxDecoration(
          color: WtmColors.panel,
          borderRadius: BorderRadius.circular(WtmRadius.sheetTop),
          border: Border.all(color: WtmColors.line),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.resultFeedbackTitle,
                style: WtmType.h2.copyWith(fontSize: 19),
              ),
              const SizedBox(height: WtmSpace.s6),
              Text(l10n.resultFeedbackSubtitle, style: WtmType.sub),
              const SizedBox(height: WtmSpace.s16),
              for (final (reason, label) in reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: WtmSpace.s8),
                  child: _ReasonTile(
                    label: label,
                    onTap: () => Navigator.of(context).pop(reason),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WtmRadius.card),
      child: Container(
        // 48dp minimum tap target (§41).
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(
          horizontal: WtmSpace.s14,
          vertical: WtmSpace.s10,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: Text(label, style: WtmType.body),
      ),
    );
  }
}

/// The restrained "WTM learned…" moment (§12.4). Shown only when the profile
/// summary genuinely changed.
class _LearnedCard extends StatelessWidget {
  const _LearnedCard({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s14),
      decoration: BoxDecoration(
        color: WtmColors.chipOnBg,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.chipOnBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WtmIcon(WtmGlyph.sparkle, size: 14, color: WtmColors.gold),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.resultLearnedTitle,
                  style: WtmType.label.copyWith(color: WtmColors.gold),
                ),
                const SizedBox(height: 2),
                Text(line, style: WtmType.sub),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
