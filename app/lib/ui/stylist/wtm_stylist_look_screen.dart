import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/wardrobe_item.dart';
import '../../features/stylist/stylist_controller.dart';
import '../../features/stylist/stylist_state.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../mirror/wtm_tryon_handoff.dart';
import '../widgets/widgets.dart';

/// Stylist look detail (board §3.18 detail view, P5) — the expanded LookCard.
/// It is the Home "Today's Look" card's destination and the Stylist screen's
/// look tap; both read the shared [stylistControllerProvider], so the pick is
/// consistent. Shows the aurora hero, the real closet pieces, the rationale as
/// an "AI insight" line, and Try This On (→ MoodMirror Step 2).
class WtmStylistLookScreen extends ConsumerStatefulWidget {
  const WtmStylistLookScreen({super.key});

  @override
  ConsumerState<WtmStylistLookScreen> createState() =>
      _WtmStylistLookScreenState();
}

class _WtmStylistLookScreenState extends ConsumerState<WtmStylistLookScreen> {
  @override
  void initState() {
    super.initState();
    // Landing here straight from Home (Today's Look) may find the stylist idle
    // — ask once so the detail has a pick to show (suggestions are free).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(stylistControllerProvider) is StylistIdle) {
        ref.read(stylistControllerProvider.notifier).styleMe();
      }
    });
  }

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
    final suggestion = state is StylistSuccess ? state.suggestion : null;

    return WtmPage(
      title: suggestion?.title ?? l10n.wtmTodaysLook,
      eyebrow: l10n.wtmStylistLookEyebrow,
      children: switch (state) {
        StylistSuccess(:final suggestion) when !suggestion.isEmpty => [
            const AuroraBox(height: 200, vignette: true),
            const SizedBox(height: WtmSpace.s12),
            Row(
              children: [
                for (final (i, item) in suggestion.items.take(4).indexed) ...[
                  if (i > 0) const SizedBox(width: 7),
                  Expanded(
                    child: FabricTile(
                      imageUrl: item.displayImageUrl,
                      swatchIndex: i,
                      fit: BoxFit.contain,
                      semanticLabel: item.title,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: WtmSpace.s12),
            Text.rich(
              TextSpan(
                text: l10n.wtmStylistInsight,
                style: WtmType.micro.copyWith(color: WtmColors.gold),
                children: [
                  TextSpan(
                    text: ' — ${suggestion.rationale}',
                    style: WtmType.micro.copyWith(height: 1.55),
                  ),
                ],
              ),
            ),
            const SizedBox(height: WtmSpace.s16),
            GradientCta(
              label: l10n.wtmStylistTryThis,
              icon: const WtmIcon(WtmGlyph.sparkle,
                  size: 15, color: WtmColors.ctaText),
              onPressed: () => _tryOn(suggestion.items),
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
              onRetry: () =>
                  ref.read(stylistControllerProvider.notifier).styleMe(),
            ),
          ],
        _ => const [
            LoadingShimmer(
              width: double.infinity,
              height: 200,
              borderRadius: BorderRadius.all(Radius.circular(WtmRadius.tile)),
            ),
          ],
      },
    );
  }
}
