import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'loading_shimmer.dart';

/// A clean, magazine flat-lay outfit preview (§5.2 Outfits tab). Up to four item
/// cutouts are laid out on a single light tile ([AppColors.tileLight]) in an
/// aligned grid — equal sizing, equal gaps, centered & upright — instead of the
/// scattered/rotated look. Shows the outfit name + a piece-count badge and an
/// optional favorite heart.
///
/// Pure presentation: pass [imageUrls], [name], [count] and callbacks. It reads
/// no providers and changes no behavior — only how the card looks.
class OutfitCard extends StatelessWidget {
  const OutfitCard({
    super.key,
    required this.imageUrls,
    required this.name,
    required this.count,
    this.isFavorite = false,
    this.onTap,
    this.onToggleFavorite,
    this.onLongPress,
  });

  final List<String> imageUrls;
  final String name;
  final int count;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.lg);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.tileLight,
                  borderRadius: radius,
                  boxShadow: AppShadow.soft,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.sm),
                        child: _FlatLay(urls: imageUrls, total: count),
                      ),
                      Positioned(
                        top: AppSpace.sm,
                        left: AppSpace.sm,
                        child: _CountBadge(count: count),
                      ),
                      if (onToggleFavorite != null)
                        Positioned(
                          top: AppSpace.xs,
                          right: AppSpace.xs,
                          child: _Heart(
                            active: isFavorite,
                            onTap: onToggleFavorite!,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aligned 1/2/4-up flat-lay of centered cutouts — never scattered.
class _FlatLay extends StatelessWidget {
  const _FlatLay({required this.urls, required this.total});

  final List<String> urls;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return const Center(
        child: Icon(Icons.style_outlined, size: 28, color: AppColors.textOnLight),
      );
    }
    if (urls.length == 1) return _Cutout(url: urls.first);

    final shown = urls.take(4).toList();
    final extra = total - shown.length;
    Widget cell(int i) {
      if (i >= shown.length) return const SizedBox.shrink();
      return _Cutout(url: shown[i], overflowMore: i == 3 && extra > 0 ? extra : 0);
    }

    if (shown.length == 2) {
      return Row(
        children: [
          Expanded(child: cell(0)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: cell(1)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(0)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: cell(1)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(2)),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: cell(3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cutout extends StatelessWidget {
  const _Cutout({required this.url, this.overflowMore = 0});

  final String url;
  final int overflowMore;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          fadeInDuration: AppMotion.base,
          placeholder: (_, _) => const LoadingShimmer(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
          ),
          errorWidget: (_, _, _) => const Center(
            child: Icon(Icons.checkroom_outlined,
                color: AppColors.textOnLight, size: 20),
          ),
        ),
        if (overflowMore > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.textOnLight.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Center(
              child: Text(
                '+$overflowMore',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.scrim,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.checkroom_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: AppShadow.soft,
        ),
        child: Icon(
          active ? Icons.favorite : Icons.favorite_border,
          size: 15,
          color: active ? AppColors.accent : AppColors.textOnLight,
        ),
      ),
    );
  }
}
