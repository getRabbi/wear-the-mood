import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import 'wtm_icons.dart';

/// Selection state badge on a tile (board `.sel` / `.addring`).
enum FabricBadge { none, add, selected }

/// Editorial image tile (board `.tile`) — the closet/grid unit. Its resting
/// face is a fabric-swatch placeholder: a c1–c8 colorway with the board's
/// bottom-left inner shade and diagonal sheen. With [imageUrl] set, a shimmer
/// pulses over the swatch while loading and the photo fades in on top
/// (UI_IMPLEMENTATION.md §0.4 loading state); on error the swatch stays — the
/// screen, not the tile, owns error messaging.
///
/// Conforms to the app's signed-URL image pattern: `cached_network_image`
/// keyed on [stableImageCacheKey] (expiring R2/Supabase query params don't
/// bust the cache) and decoded at display size.
class FabricTile extends StatelessWidget {
  const FabricTile({
    super.key,
    this.imageUrl,
    this.swatchIndex = 0,
    this.aspectRatio = 3 / 4,
    this.badge = FabricBadge.none,
    this.onTap,
    this.radius = WtmRadius.tile,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  /// Signed image URL. Null renders the pure swatch (empty tile).
  final String? imageUrl;

  /// Colorway rotation — grids pass their item index (mod 8 applied inside).
  final int swatchIndex;

  /// Board tiles are 3:4 (`.tile.sq` is 1). Null sizes from the parent.
  final double? aspectRatio;
  final FabricBadge badge;
  final VoidCallback? onTap;
  final double radius;
  final BoxFit fit;
  final String? semanticLabel;

  static const _badgeSize = 19.0; // .sel/.addring
  static const _badgeInset = 6.0; // top/right 6

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    Widget tile = RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: WtmColors.tileBorder),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: WtmSwatch.at(swatchIndex),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: WtmGradients.swatchShadeRadial,
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(gradient: WtmGradients.sheen),
              ),
              if (imageUrl != null)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final dpr = MediaQuery.of(context).devicePixelRatio;
                    final cacheW =
                        (constraints.maxWidth * dpr).clamp(64, 1080).round();
                    return CachedNetworkImage(
                      imageUrl: imageUrl!,
                      cacheKey: stableImageCacheKey(imageUrl!),
                      fit: fit,
                      alignment: Alignment.center,
                      fadeInDuration: WtmMotion.base,
                      memCacheWidth: cacheW,
                      // Soft pulse over the visible swatch (§0.4 loading).
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      // Swatch face stays on error.
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    );
                  },
                ),
              if (badge != FabricBadge.none)
                Positioned(
                  top: _badgeInset,
                  right: _badgeInset,
                  child: _TileBadge(badge),
                ),
            ],
          ),
        ),
      ),
    );
    if (aspectRatio != null) {
      tile = AspectRatio(aspectRatio: aspectRatio!, child: tile);
    }
    if (onTap == null && semanticLabel == null) return tile;
    return Semantics(
      button: onTap != null,
      image: imageUrl != null,
      selected: badge == FabricBadge.selected ? true : null,
      label: semanticLabel,
      child: onTap == null
          ? tile
          : GestureDetector(onTap: onTap, child: tile),
    );
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge(this.badge);

  final FabricBadge badge;

  @override
  Widget build(BuildContext context) {
    final selected = badge == FabricBadge.selected;
    return Container(
      width: FabricTile._badgeSize,
      height: FabricTile._badgeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected ? WtmGradients.selBadge : null,
        color: selected ? null : WtmColors.addRingBg,
        border: selected
            ? null
            : Border.all(color: WtmColors.addRingBorder),
        boxShadow: selected ? WtmShadows.selBadge : null,
      ),
      alignment: Alignment.center,
      child: WtmIcon(
        selected ? WtmGlyph.check : WtmGlyph.plus,
        size: 12, // .ic-xs
        strokeWidth: 1.7,
        color: selected ? Colors.white : WtmColors.addRingIcon,
      ),
    );
  }
}
