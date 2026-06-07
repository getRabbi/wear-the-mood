import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'loading_shimmer.dart';

/// Image-forward tile for outfits/garments — photos are the hero (CLAUDE.md §4).
/// Portrait by default (fashion). Shimmer placeholder + graceful error icon.
class OutfitTile extends StatelessWidget {
  const OutfitTile({
    super.key,
    required this.imageUrl,
    this.label,
    this.onTap,
    this.aspectRatio = 3 / 4,
  });

  final String imageUrl;
  final String? label;
  final VoidCallback? onTap;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: AppMotion.base,
                placeholder: (context, url) => const LoadingShimmer(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                ),
                errorWidget: (context, url, error) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.graphite,
                  ),
                ),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
