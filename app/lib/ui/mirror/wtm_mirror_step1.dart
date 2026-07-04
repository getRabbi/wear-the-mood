import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../data/models/tryon_photo.dart';
import '../../data/repositories/tryon_photos_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

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
    final photosAsync = ref.watch(tryonPhotosProvider);

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
        ...photosAsync.when<List<Widget>>(
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
          data: (photos) => _content(context, l10n, _selectedOf(photos)),
        ),
      ],
    );
  }

  TryonPhoto? _selectedOf(List<TryonPhoto> photos) {
    if (photos.isEmpty) return null;
    for (final p in photos) {
      if (p.isSelected) return p;
    }
    return photos.first;
  }

  List<Widget> _content(
    BuildContext context,
    AppLocalizations l10n,
    TryonPhoto? photo,
  ) {
    final url = photo?.signedUrl;
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
                      child: CachedNetworkImage(
                        imageUrl: url,
                        cacheKey: stableImageCacheKey(url),
                        fit: BoxFit.cover,
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
      const SizedBox(height: WtmSpace.s16),
      if (url != null) ...[
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
