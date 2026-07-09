import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
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
    final url = item.displayImageUrl ?? '';
    final name = closetItemName(item);
    final hasTitle = (item.title?.trim().isNotEmpty ?? false);

    return Pressable(
      onTap: onTap,
      semanticLabel: item.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Light garment tile so the cutout pops (§5.2) — centered & upright.
          // Only corner badges (heart, overflow menu) and the processing scrim
          // overlay the image; the Try-on action lives in a footer row BELOW it
          // so nothing ever covers the garment (§5.2 fix).
          Expanded(
            child: GarmentTile(
              imageUrl: url,
              overlay: Stack(
                fit: StackFit.expand,
                children: [
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
                ],
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
          else if (compact)
            // Compact cells are short — keep a single muted line, never a chip.
            Text(
              l10n.closetTapToCategorize,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: AppColors.muted),
            )
          else
            _CategorizeChip(
              onTap: () =>
                  context.push(AppRoute.wardrobeCategorize, extra: item),
            ),
          // Category pill only in the full card (compact dense grids would overflow).
          if (!compact && hasTitle && (item.category ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            _CategoryPill(label: item.category!),
          ],
          // Footer action row — below the image, never on top of it (§5.2 fix).
          if (!compact && onTryOn != null) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: l10n.closetTryOn,
                    icon: Icons.auto_awesome,
                    dense: true,
                    onPressed: onTryOn!,
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
