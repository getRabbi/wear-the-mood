import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../utils/image_format.dart';
import 'loading_shimmer.dart';

/// Editorial garment thumbnail (§5.2 — the highest-impact closet fix). A light,
/// warm tile ([AppColors.tileLight]) so clothing cutouts pop against the dark UI,
/// with the cutout centered & upright (`BoxFit.contain`), consistent padding, a
/// token radius + soft shadow. Decodes the image at display size (`memCacheWidth`)
/// and is wrapped in a [RepaintBoundary] for smooth scrolling (§8).
///
/// Pure presentation — pass the image URL plus optional [overlay] (e.g. a
/// favorite heart) and [onTap]. It does NOT read providers or change behavior.
class GarmentTile extends StatelessWidget {
  const GarmentTile({
    super.key,
    required this.imageUrl,
    this.bytes,
    this.onTap,
    this.overlay,
    this.padding = AppSpace.md,
    this.radius = AppRadius.md,
  });

  final String imageUrl;

  /// Local preview bytes (optimistic add). When set, shown INSTEAD of [imageUrl]
  /// so a just-picked photo appears instantly with no network fetch.
  final Uint8List? bytes;
  final VoidCallback? onTap;

  /// Optional overlay stacked above the image (badges, heart, actions).
  final Widget? overlay;
  final double padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final tile = RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.tileLight,
          borderRadius: borderRadius,
          boxShadow: AppShadow.soft,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.all(padding),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final dpr = MediaQuery.of(context).devicePixelRatio;
                    final cacheW = (c.maxWidth * dpr).clamp(64, 1080).round();
                    if (bytes != null) {
                      // Optimistic local preview — instant, no network.
                      // gaplessPlayback keeps the frame during the later swap to
                      // the real (background-removed) image.
                      return Image.memory(
                        bytes!,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        cacheWidth: cacheW,
                      );
                    }
                    return CachedNetworkImage(
                      imageUrl: imageUrl,
                      // Key on object identity (path), not the expiring signed
                      // URL, so a refreshed URL reuses cached bytes (1D).
                      cacheKey: stableImageCacheKey(imageUrl),
                      fit: BoxFit.contain,
                      // Upright & centered — never tilted (§5.2).
                      alignment: Alignment.center,
                      fadeInDuration: AppMotion.base,
                      memCacheWidth: cacheW,
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(
                          Icons.checkroom_outlined,
                          color: AppColors.textOnLight,
                          size: 28,
                        ),
                      ),
                    );
                  },
                ),
              ),
              ?overlay,
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}
