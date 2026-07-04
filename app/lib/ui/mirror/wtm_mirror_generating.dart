import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../features/tryon/tryon_controller.dart';
import '../../features/tryon/tryon_state.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../closet/wtm_add_garment_screen.dart' show WtmGoldProgress;
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';

/// Generating (§3.4, P4) — full-bleed aurora over the REAL job: renders
/// [tryOnControllerProvider] (reserve-at-submit → poll to terminal, §7).
/// Success replaces onto the result; failure shows the server's message with
/// the right next step (top-up on INSUFFICIENT_CREDITS, retry otherwise).
/// Cancel leaves the render finishing server-side — honestly labeled.
class WtmMirrorGeneratingScreen extends ConsumerStatefulWidget {
  const WtmMirrorGeneratingScreen({super.key});

  @override
  ConsumerState<WtmMirrorGeneratingScreen> createState() =>
      _WtmMirrorGeneratingScreenState();
}

class _WtmMirrorGeneratingScreenState
    extends ConsumerState<WtmMirrorGeneratingScreen> {
  int _line = 0;
  Timer? _cycle;

  @override
  void initState() {
    super.initState();
    _cycle = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted) setState(() => _line = (_line + 1) % 3);
    });
  }

  @override
  void dispose() {
    _cycle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(tryOnControllerProvider);

    // Success → reveal. pushReplacement keeps back = Step 3.
    ref.listen(tryOnControllerProvider, (_, next) {
      if (next is TryOnSuccess && mounted) {
        context.pushReplacement(AppRoute.wtmMirrorResult);
      }
    });

    final lines = [
      l10n.wtmMirrorGenTitle1,
      l10n.wtmMirrorGenTitle2,
      l10n.wtmMirrorGenTitle3,
    ];

    return WtmScaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuroraBox(
            borderRadius: BorderRadius.zero,
            border: false,
            vignette: true,
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
              child: switch (state) {
                TryOnFailure(:final message, :final code) => _failure(
                    context, l10n, message, code),
                _ => Column(
                    children: [
                      const Spacer(flex: 3),
                      const TheOrb(size: 120),
                      const SizedBox(height: WtmSpace.s22 + WtmSpace.s10),
                      AnimatedSwitcher(
                        duration: WtmMotion.base,
                        child: Text(
                          lines[_line],
                          key: ValueKey(_line),
                          textAlign: TextAlign.center,
                          style: WtmType.h2.copyWith(fontSize: 20),
                        ),
                      ),
                      const SizedBox(height: WtmSpace.s16),
                      const WtmGoldProgress(),
                      const SizedBox(height: WtmSpace.s12),
                      Text(
                        l10n.wtmMirrorGenHint,
                        textAlign: TextAlign.center,
                        style: WtmType.micro,
                      ),
                      const Spacer(flex: 3),
                      GhostButton(
                        label: l10n.wtmMirrorGenCancel,
                        onPressed: () {
                          wtmSnack(context, l10n.wtmMirrorGenCancelNote);
                          wtmPageBack(context);
                        },
                      ),
                      const SizedBox(height: WtmSpace.s22),
                    ],
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _failure(
    BuildContext context,
    AppLocalizations l10n,
    String message,
    String? code,
  ) {
    final needCredits = code == 'INSUFFICIENT_CREDITS';
    return Column(
      children: [
        const Spacer(flex: 2),
        WtmErrorState(
          title: l10n.wtmMirrorFailedTitle,
          message: message,
          retryLabel: l10n.wtmMirrorRetry,
          onRetry: () {
            // Back to Step 3 for another attempt.
            ref.read(tryOnControllerProvider.notifier).reset();
            wtmPageBack(context);
          },
        ),
        if (needCredits) ...[
          const SizedBox(height: WtmSpace.s10),
          GoldPill(
            label: l10n.wtmMirrorGetCredits,
            icon:
                const WtmIcon(WtmGlyph.coin, size: 12, color: WtmColors.gold),
            onTap: () => showTopUpSheet(context),
          ),
        ],
        const Spacer(flex: 3),
      ],
    );
  }
}
