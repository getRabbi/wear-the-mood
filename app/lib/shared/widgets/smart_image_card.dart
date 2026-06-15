import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'loading_shimmer.dart';

/// A polished, consistent image container (CLAUDE.md §8 image handling). Fixes
/// the "clothing looks random/floating" problem: every garment sits in the same
/// rounded card on a soft gradient, centered, with `BoxFit.contain` for cutouts
/// (no clipping) and a shimmer placeholder + graceful error fallback.
class SmartImageCard extends StatelessWidget {
  const SmartImageCard({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 1,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.onTap,
    this.padded = false,
    this.overlay,
    this.tintBackground = true,
  });

  final String imageUrl;
  final double aspectRatio;

  /// Use [BoxFit.contain] + [padded] for transparent garment cutouts; the
  /// default [BoxFit.cover] suits full-bleed photos (looks, posts).
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  /// Inset the image so a cutout doesn't touch the card edges.
  final bool padded;

  /// Optional widgets layered on top (badges, gradient + label, actions).
  final Widget? overlay;

  /// Subtle lilac wash behind the image (helps cutouts read as "in a card").
  final bool tintBackground;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    final dark = Theme.of(context).brightness == Brightness.dark;

    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      fadeInDuration: AppMotion.base,
      placeholder: (_, _) => const LoadingShimmer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.zero,
      ),
      errorWidget: (_, _, _) => Center(
        child: Icon(
          Icons.checkroom_outlined,
          color: AppColors.graphite.withValues(alpha: 0.5),
          size: 34,
        ),
      ),
    );

    if (padded) {
      image = Padding(padding: const EdgeInsets.all(AppSpace.md), child: image);
    }

    final card = ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: tintBackground
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? [const Color(0xFF271B3D), const Color(0xFF1C1430)]
                        : [const Color(0xFFF7F1FE), const Color(0xFFFBF8FE)],
                  )
                : null,
            color: tintBackground ? null : AppColors.mist,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              ?overlay,
            ],
          ),
        ),
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}
