import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../data/models/monetization.dart';
import '../../data/repositories/monetization_repository.dart';
import '../../features/paywall/monetization_gate.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_topup_sheet.dart';

/// What a free user sees once their lifetime renders are spent (RETENTION §9).
///
/// The design rule this encodes, and the reason it is a card rather than a
/// full-screen wall:
///
/// > **Hard-gate new expensive renders. Do not gate the app.**
///
/// Saved looks, planning, Style Memory, the wardrobe and browsing all stay
/// open — the user has not lost anything they already have, and the copy says
/// so. "Keep planning for free" is a real destination, listed alongside the two
/// paid options rather than buried beneath them.
///
/// Renders nothing at all for a subscriber, or for a free user with renders
/// left. Nothing here decides eligibility: the SERVER refuses an unaffordable
/// render regardless, and this card only explains why.
class WtmRenderGate extends ConsumerWidget {
  const WtmRenderGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(monetizationConfigProvider).asData?.value;
    if (config == null || !config.freeRendersExhausted) {
      return const SizedBox.shrink();
    }

    return _GateCard(
      title: l10n.renderGateTitle,
      message: l10n.renderGateMessage,
      onUnlock: () {
        ref
            .read(analyticsProvider)
            .track(
              AnalyticsEvents.paywallCtaTapped,
              properties: {'surface': MonetizationSurface.renderGate.wire},
            );
        context.push(AppRoute.wtmPaywall);
      },
      onBuyCredits: () => showTopUpSheet(context),
      onKeepPlanning: () => context.push(AppRoute.wtmMoodPlanner),
    );
  }
}

class _GateCard extends ConsumerStatefulWidget {
  const _GateCard({
    required this.title,
    required this.message,
    required this.onUnlock,
    required this.onBuyCredits,
    required this.onKeepPlanning,
  });

  final String title;
  final String message;
  final VoidCallback onUnlock;
  final VoidCallback onBuyCredits;
  final VoidCallback onKeepPlanning;

  @override
  ConsumerState<_GateCard> createState() => _GateCardState();
}

class _GateCardState extends ConsumerState<_GateCard> {
  @override
  void initState() {
    super.initState();
    // Recorded once per appearance, after the first frame. NOT interruptive:
    // the user arrived at a render screen under their own steam, so this is an
    // explanation of the state they are in, not a surface we raised at them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Through the gate, which swallows its own failures: an impression row
      // is never worth a broken screen.
      ref.read(analyticsProvider).track(AnalyticsEvents.renderGateViewed);
      ref
          .read(monetizationGateProvider)
          .recordViewed(MonetizationSurface.renderGate);
    });
  }

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
          Text(widget.title, style: WtmType.h2.copyWith(fontSize: 19)),
          const SizedBox(height: WtmSpace.s6),
          Text(widget.message, style: WtmType.sub),
          const SizedBox(height: WtmSpace.s14),
          GradientCta(label: l10n.renderGateUnlock, onPressed: widget.onUnlock),
          const SizedBox(height: WtmSpace.s8),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: l10n.renderGateBuyCredits,
                  onPressed: widget.onBuyCredits,
                ),
              ),
              const SizedBox(width: WtmSpace.s10),
              Expanded(
                // The free way out, given equal visual weight to the paid one.
                child: GhostButton(
                  label: l10n.renderGateKeepPlanning,
                  onPressed: widget.onKeepPlanning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
