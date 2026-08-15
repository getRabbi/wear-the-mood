import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/route_stack.dart';
import '../../core/router/routes.dart';
import '../../data/models/tryon_job.dart';
import '../../features/tryon/tryon_controller.dart';
import '../../features/tryon/tryon_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../closet/wtm_add_garment_screen.dart' show WtmGoldProgress;
import '../paywall/wtm_topup_sheet.dart';
import '../widgets/widgets.dart';
import 'wtm_mirror_flow.dart';

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

    // Success → reveal, and the finished wizard comes off the stack with this
    // screen.
    //
    // It used to be a `pushReplacement`, which swapped THIS page for the render
    // and left the completed steps underneath. Back from a finished look
    // therefore walked the user into the run they had just completed: the mode
    // step, then the Garments step, with a Generate button that would spend
    // credits on a render they already had. Every way back — the screen's own
    // control, the Android button, the iOS edge swipe — did it, because the
    // pages really were there.
    //
    // Repairing the stack HERE rather than intercepting Back later is what
    // makes all three agree, and it costs nothing: the render is a fresh screen
    // either way, so nothing on it is lost. Retry is unaffected — it is its own
    // control on the result, and it reopens the mode step deliberately.
    //
    // Only on SUCCESS. A failed or cancelled run leaves its steps exactly where
    // they are, because the user is going back to them.
    ref.listen(tryOnControllerProvider, (_, next) {
      if (next is TryOnSuccess && mounted) {
        replaceCompletedFlow(
          context,
          destination: AppRoute.wtmMirrorResult,
          isStep: isMirrorFlowStep,
        );
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
              padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
              child: switch (state) {
                TryOnFailure(:final message, :final code) => _failure(
                  context,
                  l10n,
                  message,
                  code,
                ),
                _ => Column(
                  children: [
                    const Spacer(flex: 3),
                    // The orb plus the ACTUAL Step-2 garments slowly orbiting
                    // it — the render visibly "works on" the outfit (QA #4).
                    _OrbWithGarments(
                      garmentUrls: [
                        for (final l in ref.watch(wtmMirrorFlowProvider).layers)
                          l.imageUrl,
                      ],
                    ),
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
                    // "Piece 2 of 4" while a multi-piece look renders. The
                    // server applies one garment per provider call and now
                    // reports which step it is on, so the wait is legible
                    // instead of an undifferentiated spinner. Absent for a
                    // single piece, where a count would say nothing.
                    if (_progress(state) case final progress?) ...[
                      Text(
                        l10n.tryOnStepProgress(progress.done, progress.total),
                        textAlign: TextAlign.center,
                        style: WtmType.micro.copyWith(color: WtmColors.gold),
                      ),
                      const SizedBox(height: WtmSpace.s6),
                    ],
                    Text(
                      l10n.wtmMirrorGenHint,
                      textAlign: TextAlign.center,
                      style: WtmType.micro,
                    ),
                    // Anything the server planned NOT to render, said out loud
                    // while the look is still being made. A piece that will not
                    // appear must never be discovered by the user noticing it is
                    // missing from the result (spec Phase 29).
                    if (_skippedCount(state) case final skipped when skipped > 0) ...[
                      const SizedBox(height: WtmSpace.s6),
                      Text(
                        l10n.tryOnPieceSkipped(skipped),
                        textAlign: TextAlign.center,
                        style: WtmType.micro.copyWith(color: WtmColors.danger),
                      ),
                    ],
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
    return _FailureBody(l10n: l10n, message: message, code: code, ref: ref);
  }

  /// The job's step progress while it is polling, or null when there is nothing
  /// worth counting (a single-piece look, or a backend that predates plans).
  ({int done, int total})? _progress(TryOnState state) =>
      state is TryOnPolling ? state.job.stepProgress : null;

  /// How many selected pieces the server left out of this look.
  int _skippedCount(TryOnState state) => switch (state) {
    TryOnPolling(:final job) => job.skipped.length,
    _ => 0,
  };
}

/// The orb with the selected garment thumbnails on a slow orbit around it —
/// one light AnimationController, tiny cached thumbs. Reduced motion → a
/// static ring (no controller ticking).
class _OrbWithGarments extends StatefulWidget {
  const _OrbWithGarments({required this.garmentUrls});

  final List<String> garmentUrls;

  static const _size = 264.0; // orbit canvas (orb 120 + ring clearance)
  static const _radius = 104.0;
  static const _thumb = 46.0;

  @override
  State<_OrbWithGarments> createState() => _OrbWithGarmentsState();
}

class _OrbWithGarmentsState extends State<_OrbWithGarments>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.garmentUrls.take(6).toList();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return SizedBox(
      width: _OrbWithGarments._size,
      height: _OrbWithGarments._size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          final base = _spin.value * 2 * math.pi;
          return Stack(
            alignment: Alignment.center,
            children: [
              const TheOrb(size: 120),
              for (final (i, url) in urls.indexed)
                Transform.translate(
                  offset: Offset(
                    _OrbWithGarments._radius *
                        math.cos(base + i * 2 * math.pi / urls.length),
                    _OrbWithGarments._radius *
                        math.sin(base + i * 2 * math.pi / urls.length),
                  ),
                  child: Container(
                    width: _OrbWithGarments._thumb,
                    height: _OrbWithGarments._thumb,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WtmColors.pillBorder),
                      color: WtmColors.panel,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      cacheKey: stableImageCacheKey(url),
                      fit: BoxFit.cover,
                      memCacheWidth: (_OrbWithGarments._thumb * dpr).round(),
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Failure body split out so the orbit widget can live beside the state class.
class _FailureBody extends StatelessWidget {
  const _FailureBody({
    required this.l10n,
    required this.message,
    required this.code,
    required this.ref,
  });

  final AppLocalizations l10n;
  final String message;
  final String? code;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final needCredits = code == 'INSUFFICIENT_CREDITS';
    final controller = ref.read(tryOnControllerProvider.notifier);
    return Column(
      children: [
        const Spacer(flex: 2),
        WtmErrorState(
          title: l10n.wtmMirrorFailedTitle,
          message: message,
          retryLabel: l10n.wtmMirrorRetry,
          // A REAL retry: re-submit the same person + outfit stack + mode as a
          // fresh job, right here (mobile QA) — reserve/refund semantics apply
          // per attempt. Out of credits → retrying can't help; back to Step 3.
          onRetry: () {
            if (!needCredits && controller.canRetry) {
              controller.retry();
            } else {
              controller.reset();
              wtmPageBack(context);
            }
          },
        ),
        if (needCredits) ...[
          const SizedBox(height: WtmSpace.s10),
          GoldPill(
            label: l10n.wtmMirrorGetCredits,
            icon: const WtmIcon(WtmGlyph.coin, size: 12, color: WtmColors.gold),
            onTap: () => showTopUpSheet(context),
          ),
        ],
        const SizedBox(height: WtmSpace.s14),
        GhostButton(
          label: l10n.wtmMirrorBackToStyling,
          onPressed: () {
            controller.reset();
            wtmPageBack(context);
          },
        ),
        const Spacer(flex: 3),
      ],
    );
  }
}
