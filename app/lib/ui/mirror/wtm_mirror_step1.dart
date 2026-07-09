import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/repositories/tryon_photos_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_body_source.dart';

/// MoodMirror Step 1 (board 03, P4) — the body photo, from the REAL try-on
/// photo gallery. Capture/manage routes into the existing consent-gated flow
/// (§10 — consent + pose validation live there; it is never bypassed).
/// With a photo on file the portal shows it and the primary action continues
/// to garments; without one, both actions go capture.
class WtmMirrorStep1Screen extends ConsumerWidget {
  const WtmMirrorStep1Screen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final choice = ref.watch(wtmBodyChoiceProvider);

    // A picked studio model / mannequin (Fix 5) overrides the photo gallery as
    // the body source; otherwise fall back to the selected try-on photo.
    final List<Widget> body;
    if (choice is WtmBodyModel) {
      body = _content(context, l10n, url: choice.model.imageUrl);
    } else if (choice is WtmBodyMannequin) {
      body = _content(context, l10n, mannequin: true);
    } else {
      body = ref.watch(tryonPhotosProvider).when<List<Widget>>(
            skipLoadingOnReload: true,
            loading: () => const [
              LoadingShimmer(
                width: double.infinity,
                height: 322,
                borderRadius: WtmRadius.arch,
              ),
            ],
            error: (_, _) => [
              WtmErrorState(
                title: l10n.wtmMirrorS1ErrorTitle,
                message: l10n.errorGenericTitle,
                retryLabel: l10n.commonRetry,
                onRetry: () => ref.invalidate(tryonPhotosProvider),
              ),
            ],
            data: (photos) {
              // Same selection the render uses (mobile QA #1) — logged for QA.
              final selected = selectedTryonPhoto(photos);
              if (kDebugMode) {
                debugPrint('[MoodMirror] Step1 preview → '
                    'photo(id=${selected?.id}, url=${selected?.signedUrl})');
              }
              return _content(context, l10n, url: selected?.signedUrl);
            },
          );
    }

    return WtmPage(
      title: l10n.wtmMirrorTitle,
      eyebrow: l10n.wtmMirrorStep(1),
      children: [
        Text(
          l10n.wtmMirrorS1Title,
          textAlign: TextAlign.center,
          style: WtmType.h2.copyWith(fontSize: 19),
        ),
        const SizedBox(height: WtmSpace.s6),
        Text(
          l10n.wtmMirrorS1Sub,
          textAlign: TextAlign.center,
          style: WtmType.sub,
        ),
        const SizedBox(height: WtmSpace.s16),
        ...body,
      ],
    );
  }

  List<Widget> _content(
    BuildContext context,
    AppLocalizations l10n, {
    String? url,
    bool mannequin = false,
  }) {
    // A body exists when a photo/model URL is present OR the mannequin is chosen.
    final hasBody = mannequin || url != null;
    return [
      // Arch portal → the body-photo manager when a photo exists (§8).
      Semantics(
        button: true,
        label: l10n.wtmMirrorS1PortalLabel,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: () => context.push(AppRoute.wtmBodyPhoto),
            child: AuroraBox(
              height: 322,
              borderRadius: WtmRadius.arch,
              vignette: true,
              child: url == null
                  ? const Center(
                      child: SizedBox(
                        width: 158,
                        height: 300,
                        child: WtmFigure(WtmFigureKind.body, opacity: 0.8),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: WtmRadius.arch,
                      child: Padding(
                        // Full-body fit inside the arch — never crop head/feet
                        // (BoxFit.contain letterboxes over the aurora ground).
                        padding: const EdgeInsets.symmetric(
                          horizontal: WtmSpace.s12,
                          vertical: WtmSpace.s10,
                        ),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          cacheKey: stableImageCacheKey(url),
                          fit: BoxFit.contain,
                          fadeInDuration: WtmMotion.base,
                          placeholder: (_, _) => const LoadingShimmer(
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: BorderRadius.zero,
                          ),
                          errorWidget: (_, _, _) => const Center(
                            child: SizedBox(
                              width: 158,
                              height: 300,
                              child:
                                  WtmFigure(WtmFigureKind.body, opacity: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(height: WtmSpace.s16),
      if (hasBody) ...[
        GradientCta(
          label: l10n.wtmMirrorS1Continue,
          icon: const WtmIcon(WtmGlyph.sparkle,
              size: 15, color: WtmColors.ctaText),
          onPressed: () => context.push(AppRoute.wtmMirrorGarments),
        ),
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.wtmMirrorS1Update,
          icon: const WtmIcon(WtmGlyph.camera,
              size: 15, color: WtmColors.text),
          onPressed: () => context.push(AppRoute.wtmBodyPhoto),
        ),
      ] else ...[
        GradientCta(
          label: l10n.wtmMirrorS1Upload,
          icon: const WtmIcon(WtmGlyph.camera,
              size: 15, color: WtmColors.ctaText),
          onPressed: () => context.push(AppRoute.wtmBodyPhoto),
        ),
        const SizedBox(height: WtmSpace.s10),
        GhostButton(
          label: l10n.wtmMirrorS1Gallery,
          icon: const WtmIcon(WtmGlyph.image,
              size: 15, color: WtmColors.text),
          onPressed: () => context.push(AppRoute.wtmBodyPhoto),
        ),
      ],
    ];
  }
}
