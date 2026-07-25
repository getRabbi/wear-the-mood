import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/stylist_suggestion.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/stylist/stylist_controller.dart';
import '../../features/stylist/stylist_state.dart';
import '../../features/stylist/weather_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../mirror/wtm_tryon_handoff.dart';
import '../widgets/widgets.dart';
import 'wtm_stylist_shared.dart';

/// WTM AI Stylist (board §3.18, P5) — the Atelier Assistant on the REAL
/// stylist backend ([stylistControllerProvider] → `POST /v1/stylist/suggest`,
/// which never charges credits). A suggestion is a title + rationale + pieces
/// from the user's OWN closet: it renders as a LookCard whose "Try This On"
/// seeds MoodMirror Step 2 (the P5 gate) and "Shuffle" re-queries. An empty
/// closet returns no pieces → EmptyState routing to Add Garment.
class WtmStylistScreen extends ConsumerStatefulWidget {
  const WtmStylistScreen({super.key});

  @override
  ConsumerState<WtmStylistScreen> createState() => _WtmStylistScreenState();
}

class _WtmStylistScreenState extends ConsumerState<WtmStylistScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh the weather when the stylist opens (uses the cache if still fresh,
    // §2) so the chip + the next suggestion reflect the current reading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(weatherControllerProvider.notifier).ensureFresh();
      // Auto-ask on first open so the screen opens on content, not an empty CTA
      // (suggestions are free — §2.1). A returning visit keeps the last pick.
      if (ref.read(stylistControllerProvider) is StylistIdle) {
        ref.read(stylistControllerProvider.notifier).styleMe();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On returning to the app, refresh the weather if it's gone stale (§2).
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(weatherControllerProvider.notifier).ensureFresh();
    }
  }

  void _shuffle() => ref.read(stylistControllerProvider.notifier).styleMe();

  void _tryOn(List<WardrobeItem> items) {
    final l10n = AppLocalizations.of(context);
    if (!wtmTryOnWithItems(context, ref, items)) {
      wtmSnack(context, l10n.wtmTryOnNoImage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(stylistControllerProvider);

    return WtmPage(
      title: l10n.wtmStylistTitle,
      eyebrow: l10n.wtmStylistEyebrow,
      children: [
        const WtmStylistGreeting(),
        const SizedBox(height: WtmSpace.s12),
        const WtmStylistContextChips(),
        const SizedBox(height: WtmSpace.s14),
        ...switch (state) {
          StylistSuccess(:final suggestion) when !suggestion.isEmpty => [
              _StylistLookCard(
                suggestion: suggestion,
                onOpen: () => context.push(AppRoute.wtmStylistLook),
                onTryOn: () => _tryOn(suggestion.items),
                onShuffle: _shuffle,
              ),
            ],
          StylistSuccess() => [
              WtmEmptyState(
                glyph: WtmGlyph.hanger,
                title: l10n.wtmStylistEmptyTitle,
                message: l10n.wtmStylistEmptyMessage,
                ctaLabel: l10n.wtmStylistEmptyCta,
                onCta: () => context.push(AppRoute.wtmClosetAdd),
              ),
            ],
          StylistFailure(:final message) => [
              WtmErrorState(
                title: l10n.wtmStylistErrorTitle,
                message: message,
                retryLabel: l10n.commonRetry,
                onRetry: _shuffle,
              ),
            ],
          _ => const [_StylistLookSkeleton()],
        },
      ],
    );
  }
}

/// A LookCard (board §3.18): name → tap opens the look detail; a mini-row of
/// the real closet pieces; Try This On (gradient) + Shuffle (ghost).
class _StylistLookCard extends StatelessWidget {
  const _StylistLookCard({
    required this.suggestion,
    required this.onOpen,
    required this.onTryOn,
    required this.onShuffle,
  });

  final StylistSuggestion suggestion;
  final VoidCallback onOpen;
  final VoidCallback onTryOn;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pieces = suggestion.items.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: '${l10n.wtmStylistOpenLook}: ${suggestion.title}',
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Row(
                  children: [
                    Expanded(child: wtmLookTitle(suggestion.title)),
                    const WtmIcon(WtmGlyph.chevron,
                        size: 15, color: WtmColors.faint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: WtmSpace.s10),
          Row(
            children: [
              for (final (i, item) in pieces.indexed) ...[
                if (i > 0) const SizedBox(width: 7),
                Expanded(
                  child: FabricTile(
                    imageUrl: item.displayImageUrl,
                    swatchIndex: i,
                    fit: BoxFit.contain,
                    radius: 9,
                    semanticLabel: item.title,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: WtmSpace.s12),
          Row(
            children: [
              Expanded(
                child: GradientCta(
                  label: l10n.wtmStylistTryThis,
                  icon: const WtmIcon(WtmGlyph.sparkle,
                      size: 15, color: WtmColors.ctaText),
                  onPressed: onTryOn,
                ),
              ),
              const SizedBox(width: WtmSpace.s10),
              SizedBox(
                width: 104,
                child: GhostButton(
                  label: l10n.wtmStylistShuffle,
                  onPressed: onShuffle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder — a LookCard-shaped shimmer.
class _StylistLookSkeleton extends StatelessWidget {
  const _StylistLookSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: WtmGradients.cardFill,
        borderRadius: BorderRadius.circular(WtmRadius.card),
        border: Border.all(color: WtmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LoadingShimmer(width: 180, height: 22),
          const SizedBox(height: WtmSpace.s12),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                const Expanded(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius:
                          BorderRadius.all(Radius.circular(9)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: WtmSpace.s12),
          const LoadingShimmer(
            width: double.infinity,
            height: 48,
            borderRadius: BorderRadius.all(Radius.circular(WtmRadius.button)),
          ),
        ],
      ),
    );
  }
}
