import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/widgets.dart';
import 'closet_drawer.dart';

/// A lightweight 2.5D "drawer" card (CLAUDE.md §4) — a glass panel tinted with
/// the drawer's accent, with peeking item thumbnails and a drawer-pull / hanger
/// hint so it reads like furniture, not a product tile. No heavy 3D.
class DrawerCard extends StatelessWidget {
  const DrawerCard({
    super.key,
    required this.drawer,
    required this.count,
    required this.previews,
    required this.onTap,
    this.onMenu,
  });

  final ClosetDrawer drawer;
  final int count;

  /// Up to 3 image URLs of the latest items, peeking out of the drawer.
  final List<String> previews;
  final VoidCallback onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final accent = drawer.accent;
    final isRail = drawer.kind == ClosetDrawerKind.rail;

    return Pressable(
      onTap: onTap,
      semanticLabel: drawer.name,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0.20),
              Theme.of(context).colorScheme.surface,
            ],
            stops: const [0, 0.6],
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadow.soft,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rail = hanger hook; drawer = pull handle.
              Center(
                child: Icon(
                  isRail ? Icons.architecture_rounded : Icons.remove_rounded,
                  size: 18,
                  color: accent.withValues(alpha: 0.7),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(drawer.icon, size: 18, color: accent),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      drawer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(fontSize: 15),
                    ),
                  ),
                  if (onMenu != null)
                    GestureDetector(
                      onTap: onMenu,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.more_horiz_rounded,
                            size: 18, color: AppColors.graphite),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Expanded(child: _Previews(urls: previews, accent: accent)),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.wardrobeItemsCount(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: count == 0
                            ? AppColors.muted
                            : AppColors.lavender,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: accent.withValues(alpha: 0.8)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Previews extends StatelessWidget {
  const _Previews({required this.urls, required this.accent});

  final List<String> urls;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: accent.withValues(alpha: 0.25),
            // dashed feel via a thin border
          ),
        ),
        child: Center(
          child: Icon(Icons.add_rounded, color: accent.withValues(alpha: 0.7)),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < urls.length && i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: CachedNetworkImage(
                      imageUrl: urls[i],
                      fit: BoxFit.contain,
                      placeholder: (_, _) =>
                          const ColoredBox(color: AppColors.paperAlt),
                      errorWidget: (_, _, _) => const Icon(
                        Icons.checkroom_outlined,
                        size: 16,
                        color: AppColors.graphite,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        // Pad out to keep a stable 3-slot layout.
        for (var i = urls.length; i < 3; i++) ...[
          const SizedBox(width: 6),
          const Expanded(child: SizedBox()),
        ],
      ],
    );
  }
}
