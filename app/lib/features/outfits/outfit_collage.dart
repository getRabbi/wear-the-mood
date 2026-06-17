import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/outfit.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../wardrobe/wardrobe_providers.dart';

/// Resolves an outfit's piece images (cutouts) from the loaded closet, in the
/// outfit's saved order. Falls back to the cover image when items aren't loaded.
List<String> outfitImageUrls(Outfit outfit, List<WardrobeItem> closet) {
  final byId = {for (final i in closet) i.id: i};
  final urls = <String>[
    for (final id in outfit.itemIds) ?byId[id]?.displayImageUrl,
  ];
  if (urls.isEmpty && (outfit.coverImageUrl?.isNotEmpty ?? false)) {
    urls.add(outfit.coverImageUrl!);
  }
  return urls;
}

/// A polished outfit card showing a preview collage board (up to four pieces)
/// instead of just a cover + count (spec). Heart toggles favorite; the count
/// badge reflects the real number of saved pieces.
class OutfitCollageCard extends ConsumerWidget {
  const OutfitCollageCard({
    super.key,
    required this.outfit,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onLongPress,
  });

  final Outfit outfit;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final closet = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    final urls = outfitImageUrls(outfit, closet);
    final name = (outfit.name?.trim().isNotEmpty ?? false)
        ? outfit.name!.trim()
        : l10n.outfitsUntitled;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CollageBoard(urls: urls, total: outfit.itemCount),
                  Positioned(
                    top: AppSpace.sm,
                    left: AppSpace.sm,
                    child: _CountBadge(count: outfit.itemCount),
                  ),
                  Positioned(
                    top: AppSpace.xs,
                    right: AppSpace.xs,
                    child: _CircleIcon(
                      icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? AppColors.accent : null,
                      onTap: onToggleFavorite,
                    ),
                  ),
                ],
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
    );
  }
}

class _CollageBoard extends StatelessWidget {
  const _CollageBoard({required this.urls, required this.total});

  final List<String> urls;
  final int total;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final board = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [const Color(0xFF271B3D), const Color(0xFF1C1430)]
              : [const Color(0xFFF7F1FE), const Color(0xFFFBF8FE)],
        ),
      ),
      child: _grid(),
    );
    return board;
  }

  Widget _grid() {
    if (urls.isEmpty) {
      return const Center(
        child: Icon(Icons.style_outlined, size: 30, color: AppColors.graphite),
      );
    }
    if (urls.length == 1) return _cell(urls.first);

    // 2 → two columns; 3–4 → 2×2. The 4th cell shows "+N" when there's more.
    final shown = urls.take(4).toList();
    final extra = total - shown.length;
    Widget cellAt(int i) {
      if (i >= shown.length) return const ColoredBox(color: Colors.transparent);
      final isLast = i == 3 && extra > 0;
      return _cell(shown[i], overflowMore: isLast ? extra : 0);
    }

    if (shown.length == 2) {
      return Row(
        children: [
          Expanded(child: cellAt(0)),
          Expanded(child: cellAt(1)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: cellAt(0)),
              Expanded(child: cellAt(1)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: cellAt(2)),
              Expanded(child: cellAt(3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(String url, {int overflowMore = 0}) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            fadeInDuration: AppMotion.base,
            errorWidget: (_, _, _) => const Icon(
              Icons.checkroom_outlined,
              color: AppColors.graphite,
              size: 22,
            ),
          ),
          if (overflowMore > 0)
            ColoredBox(
              color: AppColors.scrim,
              child: Center(
                child: Text(
                  '+$overflowMore',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.scrim,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.checkroom_rounded, size: 13, color: Colors.white),
          const SizedBox(width: AppSpace.xs),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

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
        child: Icon(icon, size: 16, color: color ?? AppColors.graphite),
      ),
    );
  }
}
