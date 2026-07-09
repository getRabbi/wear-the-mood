import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
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
    return _FailureBody(l10n: l10n, message: message, code: code, ref: ref);
  }
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
