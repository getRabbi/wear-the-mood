import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Card geometry (DISCOVER spec §6.2).
///
/// Responsive rather than device-specific: the width is a fraction of the
/// viewport, clamped to the spec's 128–138 range on phones, so roughly 2.4–2.8
/// cards sit in view on a phone and a tablet shows more without inflating them
/// into banners. Every card is the same size — the first is NOT special (§6.2).
abstract final class WtmStoryCardMetrics {
  static const phoneMinWidth = 128.0;
  static const phoneMaxWidth = 138.0;
  static const tabletMaxWidth = 172.0;

  /// Portrait, ~1.47:1 — inside the spec's 188–204 height for the width range.
  static const aspectRatio = 1.47;

  static const gap = WtmSpace.s10;

  /// Width breakpoint at which the layout is treated as a tablet.
  static const tabletBreakpoint = 600.0;

  /// Card width for a viewport of [viewportWidth].
  static double widthFor(double viewportWidth) {
    final isTablet = viewportWidth >= tabletBreakpoint;
    // ~2.6 cards visible on a phone; proportionally larger, but capped, on a
    // tablet so more cards show rather than bigger ones.
    final target = (viewportWidth - WtmSpace.screenH * 2) / 2.6;
    return target.clamp(
      phoneMinWidth,
      isTablet ? tabletMaxWidth : phoneMaxWidth,
    );
  }

  static double heightFor(double viewportWidth) =>
      widthFor(viewportWidth) * aspectRatio;
}

/// The horizontal Discover Stories rail (§6).
///
/// A portrait-card rail, not a row of circular avatars (§26.17). The caller is
/// responsible for deciding whether there are enough cards to warrant a rail
/// at all — see [DiscoverRail.minCards].
class WtmStoryRail extends StatelessWidget {
  const WtmStoryRail({
    super.key,
    required this.stories,
    required this.seenIds,
    required this.onTap,
    this.controller,
    this.wrapCard,
  });

  final List<DiscoverStory> stories;

  /// Ids already seen at their current version. Drives the ring treatment.
  final Set<String> seenIds;

  final void Function(DiscoverStory story, int index) onTap;

  /// Owned by the screen so the rail's scroll offset survives a rebuild and a
  /// return from the viewer (§6.5 "preserve rail scroll position").
  final ScrollController? controller;

  /// Optional decorator, used to attach impression tracking without the rail
  /// having to know what analytics is.
  final Widget Function(DiscoverStory story, int index, Widget card)? wrapCard;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = WtmStoryCardMetrics.widthFor(width);
    final cardHeight = WtmStoryCardMetrics.heightFor(width);

    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        // The rail lives inside the screen's vertical scroll view; its own
        // physics stay horizontal-only so the two never fight (§23, and the
        // "no nested-scroll conflict" QA item in §41).
        padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
        itemCount: stories.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: WtmStoryCardMetrics.gap),
        itemBuilder: (context, index) {
          final story = stories[index];
          final card = WtmStoryCard(
            story: story,
            seen: seenIds.contains(story.id),
            width: cardWidth,
            height: cardHeight,
            onTap: () => onTap(story, index),
          );
          return wrapCard?.call(story, index, card) ?? card;
        },
      ),
    );
  }
}

/// One portrait story card (§6.3).
class WtmStoryCard extends StatelessWidget {
  const WtmStoryCard({
    super.key,
    required this.story,
    required this.seen,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final DiscoverStory story;
  final bool seen;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Unseen gets the violet→pink AI gradient ring; seen drops to a quiet
    // neutral line. A subtle premium ring, never a rainbow (§6.4).
    final border = seen
        ? Border.all(color: WtmColors.line)
        : Border.all(
            color: WtmColors.orchid.withValues(alpha: 0.55),
            width: 1.4,
          );

    return Semantics(
      button: true,
      // Category, title, freshness and the action — freshness is SPOKEN, so
      // unseen state is never carried by ring colour alone (§6.6).
      label: [
        story.category,
        story.title,
        if (story.subtitle != null) story.subtitle,
        seen ? l10n.wtmStorySemanticSeen : l10n.wtmStorySemanticNew,
      ].join('. '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: border,
              gradient: WtmGradients.cardFill,
            ),
            // Clip inside the border so artwork never paints over the ring.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WtmRadius.card - 1),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(story: story),
                  // Bottom scrim for legibility over any image (§6.3).
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xCC05030A)],
                        stops: [0.42, 1.0],
                      ),
                    ),
                  ),
                  if (story.badge != null)
                    Positioned(
                      top: WtmSpace.s8,
                      right: WtmSpace.s8,
                      child: _Badge(label: story.badge!),
                    ),
                  Positioned(
                    left: WtmSpace.s10,
                    right: WtmSpace.s10,
                    bottom: WtmSpace.s10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          story.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.micro.copyWith(
                            fontSize: 8,
                            letterSpacing: 0.96,
                            color: WtmColors.gold,
                          ),
                        ),
                        const SizedBox(height: WtmSpace.s4),
                        Text(
                          story.title,
                          // Two lines maximum (§6.3, §25).
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.h2.copyWith(
                            fontSize: 15,
                            height: 1.2,
                            color: WtmColors.text,
                          ),
                        ),
                        if (story.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            story.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WtmType.micro.copyWith(
                              color: WtmColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's backdrop: the story's image where it has one, otherwise the
/// aurora artwork. A story without an image is normal, not an error — it must
/// never leave a hole (§6.3, §23 "image error fallback").
class _Artwork extends StatelessWidget {
  const _Artwork({required this.story});

  final DiscoverStory story;

  @override
  Widget build(BuildContext context) {
    final url = story.imageUrl;
    if (url == null || url.isEmpty) {
      return const AuroraBox(height: double.infinity, vignette: true);
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: stableImageCacheKey(url),
      fit: BoxFit.cover,
      // Decode at card size, not full resolution — a rail of full-res photos
      // is the fastest way to make Discover stutter (§23).
      memCacheWidth: 420,
      placeholder: (_, _) =>
          const AuroraBox(height: double.infinity, vignette: true),
      errorWidget: (_, _, _) =>
          const AuroraBox(height: double.infinity, vignette: true),
    );
  }
}

/// A single small badge. At most one per card (§26.11).
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.s6, vertical: 3),
      decoration: BoxDecoration(
        color: WtmColors.pillBg,
        border: Border.all(color: WtmColors.pillBorder),
        borderRadius: BorderRadius.circular(WtmRadius.chip),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: WtmType.micro.copyWith(
          fontSize: 8,
          letterSpacing: 0.8,
          color: WtmColors.gold,
        ),
      ),
    );
  }
}

/// The compact fallback shown instead of a rail when fewer than
/// [DiscoverRail.minCards] stories are eligible — a one-card scroller looks
/// broken, so the spec asks for a different shape rather than a thin rail
/// (§6.1).
class WtmStoryFallbackCard extends StatelessWidget {
  const WtmStoryFallbackCard({
    super.key,
    required this.story,
    required this.onTap,
  });

  final DiscoverStory story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [
        story.category,
        story.title,
        if (story.subtitle != null) story.subtitle,
      ].join('. '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(WtmSpace.s14),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        story.category.toUpperCase(),
                        style: WtmType.micro.copyWith(
                          fontSize: 8,
                          letterSpacing: 0.96,
                          color: WtmColors.gold,
                        ),
                      ),
                      const SizedBox(height: WtmSpace.s4),
                      Text(
                        story.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.h2.copyWith(fontSize: 16, height: 1.25),
                      ),
                      if (story.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          story.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.micro,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: WtmSpace.s10),
                const WtmIcon(
                  WtmGlyph.chevron,
                  size: 16,
                  color: WtmColors.gold,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
