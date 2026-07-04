import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/credits_repository.dart';
import '../../features/tryon/sample_garments.dart';
import '../../features/tryon/tryon_controller.dart';
import '../../features/tryon/two_d/two_d_editor_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';
import 'wtm_body_source.dart';
import 'wtm_mirror_flow.dart';

/// MoodMirror Step 3 (board 05, P4) — mode + REAL credit gating. Costs and the
/// Pro-Max HD gate come from the server-backed [creditsProvider] (the server
/// stays the authority; this mirror just saves a round-trip, §12/§18).
/// Insufficient credits → inline warning + Get credits, Generate disabled
/// (§3.1). 2D opens the free on-device studio; AI submits the metered job.
class WtmMirrorStep3Screen extends ConsumerWidget {
  const WtmMirrorStep3Screen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(wtmMirrorFlowProvider);
    final creditsAsync = ref.watch(creditsProvider);
    final credits = creditsAsync.asData?.value;
    final mode = draft.mode;

    final cost = mode.cost(credits);
    final planLocked = !mode.allowed(credits);
    final spendable = credits?.totalAvailable ?? 0;
    final short = mode.isAi && !planLocked && spendable < cost;
    final canGenerate =
        draft.layers.isNotEmpty && !planLocked && !short;

    return WtmPage(
      title: l10n.wtmMirrorTitle,
      eyebrow: l10n.wtmMirrorStep(3),
      children: [
        Text(
          l10n.wtmMirrorS3Title,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 19),
        ),
        const SizedBox(height: WtmSpace.s6),
        Text(
          l10n.wtmMirrorS3Sub,
          textAlign: TextAlign.center,
          style: WtmType.sub,
        ),
        const SizedBox(height: WtmSpace.s14),
        _ModeCard(
          title: l10n.wtmMirrorMode2dTitle,
          subtitle: l10n.wtmMirrorMode2dSub,
          swatchIndex: 6,
          badge: const WtmBadge.free(),
          on: mode == WtmMirrorMode.twoD,
          onTap: () => ref
              .read(wtmMirrorFlowProvider.notifier)
              .setMode(WtmMirrorMode.twoD),
        ),
        const SizedBox(height: 9),
        _ModeCard(
          title: l10n.wtmMirrorModeAiTitle,
          subtitle: l10n.wtmMirrorModeAiSub,
          swatchIndex: 2,
          badge: _CreditChip(
            label: (credits?.stdCost ?? 1) == 1
                ? l10n.wtmMirrorCreditChipOne
                : l10n.wtmMirrorCreditChip(credits?.stdCost ?? 1),
          ),
          on: mode == WtmMirrorMode.aiCouture,
          onTap: () => ref
              .read(wtmMirrorFlowProvider.notifier)
              .setMode(WtmMirrorMode.aiCouture),
        ),
        const SizedBox(height: 9),
        _ModeCard(
          title: l10n.wtmMirrorModeHdTitle,
          subtitle: l10n.wtmMirrorModeHdSub,
          swatchIndex: 5,
          badge: const WtmBadge.pro(),
          on: mode == WtmMirrorMode.fullLook,
          // Locked tier: the PRO badge (and card) routes to the paywall (§8).
          onTap: (credits?.hdAllowed ?? false)
              ? () => ref
                  .read(wtmMirrorFlowProvider.notifier)
                  .setMode(WtmMirrorMode.fullLook)
              : () => context.push(AppRoute.wtmPaywall),
          onBadgeTap: (credits?.hdAllowed ?? false)
              ? null
              : () => context.push(AppRoute.wtmPaywall),
        ),
        if (mode == WtmMirrorMode.fullLook && planLocked) ...[
          const SizedBox(height: WtmSpace.s8),
          Text(l10n.wtmMirrorHdLocked, style: WtmType.micro),
        ],
        const SizedBox(height: WtmSpace.s16),
        // Credits row — real balance; tap → top-up sheet (§8).
        Semantics(
          button: true,
          label: '${l10n.wtmMirrorCreditsEyebrow}: $spendable',
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showTopUpSheet(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: WtmColors.pillBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: WtmColors.pillBorder),
                ),
                child: Row(
                  children: [
                    EyebrowLabel(l10n.wtmMirrorCreditsEyebrow),
                    const Spacer(),
                    const WtmIcon(WtmGlyph.coin,
                        size: 15, color: WtmColors.gold),
                    const SizedBox(width: WtmSpace.s6),
                    if (creditsAsync.isLoading && credits == null)
                      const LoadingShimmer(width: 40, height: 18)
                    else
                      Text(
                        '$spendable',
                        style: WtmType.h2
                            .copyWith(fontSize: 17, color: WtmColors.gold),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // §3.1: insufficient credits → inline warning + Get credits pill.
        if (short) ...[
          const SizedBox(height: WtmSpace.s10),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.wtmMirrorNeedCredits,
                  style: WtmType.micro.copyWith(color: WtmColors.danger),
                ),
              ),
              GoldPill(
                label: l10n.wtmMirrorGetCredits,
                onTap: () => showTopUpSheet(context),
              ),
            ],
          ),
        ],
        const SizedBox(height: WtmSpace.s14),
        GradientCta(
          label: mode.isTwoD ? l10n.wtmMirrorOpen2d : l10n.wtmMirrorGenerate,
          icon: const WtmIcon(WtmGlyph.sparkle,
              size: 15, color: WtmColors.ctaText),
          onPressed: canGenerate ? () => _generate(context, ref) : null,
        ),
        const SizedBox(height: WtmSpace.s10),
        Text(
          mode.isTwoD
              ? l10n.wtmMirrorCostNoteFree
              : l10n.wtmMirrorCostNote(cost),
          textAlign: TextAlign.center,
          style: WtmType.micro,
        ),
      ],
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(wtmMirrorFlowProvider);
    // Body: the chosen studio model / mannequin (Fix 5), else the selected
    // try-on photo, else the sample stand-in (activation before capture).
    final body = ref.read(wtmBodyImageProvider);

    if (draft.mode.isTwoD) {
      // Free on-device studio — no backend, no credits. An empty body URL puts
      // the 2D editor into its built-in mannequin mode.
      final bodyUrl = body.mannequin ? '' : (body.url ?? samplePersonImageUrl);
      await context.push(
        AppRoute.tryon2dEditor,
        extra: TwoDEditorArgs(bodyImageUrl: bodyUrl, layers: draft.layers),
      );
      return;
    }
    // Metered AI render — reserve-at-submit; the controller polls to terminal.
    // The mannequin can't be photographed, so AI falls back to the sample body
    // (only the free 2D path renders on the mannequin).
    final personUrl =
        (body.mannequin ? null : body.url) ?? samplePersonImageUrl;
    ref.read(tryOnControllerProvider.notifier).start(
          personImageUrl: personUrl,
          garmentImageUrls: [for (final l in draft.layers) l.imageUrl],
          hd: draft.mode.hd,
        );
    context.push(AppRoute.wtmMirrorGenerating);
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.swatchIndex,
    required this.badge,
    required this.on,
    required this.onTap,
    this.onBadgeTap,
  });

  final String title;
  final String subtitle;
  final int swatchIndex;
  final Widget badge;
  final bool on;
  final VoidCallback onTap;
  final VoidCallback? onBadgeTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: WtmMotion.fast,
            curve: WtmMotion.easing,
            padding: const EdgeInsets.all(11), // .modecard
            decoration: BoxDecoration(
              color: on ? WtmColors.chipOnBg : null,
              gradient: on ? null : WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: on ? WtmColors.chipOnBorder : WtmColors.line),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  height: 58, // .mthumb
                  child: FabricTile(
                    swatchIndex: swatchIndex,
                    aspectRatio: null,
                    radius: 11,
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: WtmType.labelMedium),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: WtmType.micro.copyWith(height: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(width: WtmSpace.s8),
                GestureDetector(onTap: onBadgeTap, child: badge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The metered-mode cost chip (real `std_cost` — an honest stand-in for the
/// board's PRO badge on a mode that is credit-gated, not plan-gated).
class _CreditChip extends StatelessWidget {
  const _CreditChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WtmRadius.chip),
        border: Border.all(color: WtmColors.pillBorder),
        color: WtmColors.pillBg,
      ),
      child: Text(
        label.toUpperCase(),
        style: WtmType.micro.copyWith(
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.7,
          color: WtmColors.gold,
        ),
      ),
    );
  }
}
