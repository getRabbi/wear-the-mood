import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_item.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'closet_category.dart';

/// Polished closet grid card (redesign spec). A consistent image area (cutout on
/// a soft wash, `BoxFit.contain`, centered — never floating) with a favorite
/// heart, overflow menu, and a Try-on / Style-it action row overlaid at the
/// bottom; the piece's name + category sit beneath. Uses [Expanded] for the
/// image so it never overflows its grid cell.
class ClosetItemCard extends StatelessWidget {
  const ClosetItemCard({
    super.key,
    required this.item,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.onTryOn,
    this.onStyle,
    this.onMenu,
    this.compact = false,
  });

  final WardrobeItem item;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onTryOn;
  final VoidCallback? onStyle;
  final VoidCallback? onMenu;

  /// Hides the action row (used in dense previews like the Profile closet tab).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final url = item.displayImageUrl ?? '';
    final name = closetItemName(item);
    final hasTitle = (item.title?.trim().isNotEmpty ?? false);

    return Pressable(
      onTap: onTap,
      semanticLabel: item.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? [const Color(0xFF271B3D), const Color(0xFF1C1430)]
                        : [const Color(0xFFF7F1FE), const Color(0xFFFBF8FE)],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
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
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                    if (onMenu != null)
                      Positioned(
                        top: AppSpace.xs,
                        left: AppSpace.xs,
                        child: _CircleIcon(
                          icon: Icons.more_horiz_rounded,
                          onTap: onMenu!,
                        ),
                      ),
                    Positioned(
                      top: AppSpace.xs,
                      right: AppSpace.xs,
                      child: _CircleIcon(
                        icon: isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: isFavorite ? AppColors.accent : null,
                        onTap: onToggleFavorite,
                      ),
                    ),
                    if (!compact && onTryOn != null)
                      Positioned(
                        left: AppSpace.sm,
                        right: AppSpace.sm,
                        bottom: AppSpace.sm,
                        child: Row(
                          children: [
                            Expanded(
                              child: _MiniButton(
                                label: l10n.closetTryOn,
                                icon: Icons.auto_awesome,
                                onTap: onTryOn!,
                              ),
                            ),
                            if (onStyle != null) ...[
                              const SizedBox(width: AppSpace.xs),
                              _CircleIcon(
                                icon: Icons.style_outlined,
                                filled: true,
                                onTap: onStyle!,
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (item.isProcessingCutout)
                      const Positioned.fill(child: _ProcessingScrim()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (name != null)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(fontSize: 14),
            )
          else
            _CategorizeChip(onTap: onTap),
          if (hasTitle && (item.category ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            _CategoryPill(label: item.category!),
          ],
        ],
      ),
    );
  }
}

/// Small lavender category pill shown under a named piece.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.lavender,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a plain "Uncategorized" label when a piece has no name yet.
class _CategorizeChip extends StatelessWidget {
  const _CategorizeChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sell_outlined, size: 13, color: AppColors.lavender),
              const SizedBox(width: 4),
              Text(
                l10n.closetTapToCategorize,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.lavender,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({
    required this.icon,
    required this.onTap,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: filled
              ? AppColors.accent
              : Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: AppShadow.soft,
        ),
        child: Icon(
          icon,
          size: 16,
          color: filled ? Colors.white : (color ?? AppColors.graphite),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Covers a tile while its background-removal cutout is still generating (§2.2).
class _ProcessingScrim extends StatelessWidget {
  const _ProcessingScrim();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.scrim),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              ),
              const SizedBox(height: AppSpace.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Text(
                  l10n.wardrobeRemovingBackground,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
