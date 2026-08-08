import 'package:flutter/material.dart';

import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_discover_artwork.dart';

/// Card geometry (DISCOVER spec §6.2).
///
/// Responsive rather than device-specific: the width is a fraction of the
/// viewport, clamped to the spec's 128–138 range on phones, so roughly 2.4–2.8
/// cards sit in view on a phone and a tablet shows more without inflating them
/// into banners. Every card is the same size — the first is NOT special (§6.2).
abstract final class WtmStoryCardMetrics {
  static const gap = DiscoverTokens.storyGap;

  /// Width breakpoint at which the layout is treated as a tablet.
  static const tabletBreakpoint = 600.0;

  static const tabletMaxWidth = 172.0;

  /// The prototype fixes 132×194, dropping to 122×184 under its 350px
  /// breakpoint. A tablet is allowed to grow the card a little so more cards
  /// show rather than bigger ones.
  static double widthFor(double viewportWidth) {
    if (viewportWidth <= DiscoverTokens.narrowBreakpoint) {
      return DiscoverTokens.storyWidthNarrow;
    }
    if (viewportWidth < tabletBreakpoint) return DiscoverTokens.storyWidth;
    return (viewportWidth / 5.4).clamp(
      DiscoverTokens.storyWidth,
      tabletMaxWidth,
    );
  }

  static double heightFor(double viewportWidth) {
    if (viewportWidth <= DiscoverTokens.narrowBreakpoint) {
      return DiscoverTokens.storyHeightNarrow;
    }
    // Keeps the prototype's 132:194 proportion as the card scales up.
    return widthFor(viewportWidth) *
        (DiscoverTokens.storyHeight / DiscoverTokens.storyWidth);
  }
}

/// The silhouette drawn on each kind of story card when there is no image —
/// the prototype's six distinct card treatments, one per type.
WtmGlyph wtmStoryGlyph(DiscoverStoryType type) => switch (type) {
  DiscoverStoryType.dailyEdit => WtmGlyph.sparkle,
  DiscoverStoryType.closetMatch => WtmGlyph.hanger,
  DiscoverStoryType.newForYou => WtmGlyph.shirt,
  DiscoverStoryType.giveaway => WtmGlyph.gift,
  DiscoverStoryType.offer => WtmGlyph.coin,
  DiscoverStoryType.newsroom => WtmGlyph.bookmark,
};

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
        padding: EdgeInsets.symmetric(horizontal: DiscoverTokens.padFor(width)),
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
              borderRadius: BorderRadius.circular(DiscoverTokens.radiusStory),
              // Unseen wears the prototype's three-stop ring (violet → pink →
              // gold), painted as a 1.5px gradient border; seen drops to a
              // quiet neutral line. A premium ring, never a rainbow (§6.4).
              gradient: seen ? null : DiscoverTokens.freshRing,
              border: seen
                  ? Border.all(color: DiscoverTokens.storyBorder)
                  : null,
              boxShadow: const [
                // `0 14px 40px rgba(0,0,0,.28)`
                BoxShadow(
                  color: Color(0x47000000),
                  blurRadius: 40,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            padding: EdgeInsets.all(seen ? 0 : 1.5),
            // Clip inside the ring so artwork never paints over it.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                DiscoverTokens.radiusStory - 1.5,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(story: story),
                  // Bottom scrim for legibility over any image (§6.3).
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: DiscoverTokens.storyScrim,
                    ),
                  ),
                  // `.story-badge { top: 11px; left: 11px }`
                  if (story.badge != null)
                    Positioned(
                      top: 11,
                      left: 11,
                      child: _Badge(label: story.badge!),
                    ),
                  Positioned(
                    // `.story-content { left/right/bottom: 13px }`
                    left: 13,
                    right: 13,
                    bottom: 13,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          story.category.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DiscoverTokens.storyLabelStyle,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          story.title,
                          // Two lines maximum (§6.3, §25).
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: DiscoverTokens.storyTitleStyle,
                        ),
                        if (story.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            story.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DiscoverTokens.storyMetaStyle,
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

/// The card's backdrop: the story's image where it has one, otherwise a drawn
/// card carrying the story's own silhouette. A story without an image is
/// normal, not an error — it must never leave a hole (§6.3, §23 "image error
/// fallback"), and it must not leave six identical rectangles either, which is
/// what the prototype's six distinct card treatments are there to prevent.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.story});

  final DiscoverStory story;

  @override
  Widget build(BuildContext context) {
    return WtmDiscoverArtwork(
      url: story.imageUrl,
      // Seeded on the TYPE, so the six rail cards are six different colours in
      // the prototype's own order rather than a random scatter.
      seed: story.type.name,
      glyph: wtmStoryGlyph(story.type),
      // Decode at card size, not full resolution — a rail of full-res photos
      // is the fastest way to make Discover stutter (§23).
      decodeWidth: 420,
      glyphScale: 0.48,
    );
  }
}

/// A single small badge. At most one per card (§26.11).
/// `.story-badge` — a glass capsule, white on smoked plum.
class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.story-badge { padding: 6px 8px }`
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DiscoverTokens.badgeBg,
        border: Border.all(color: DiscoverTokens.badgeBorder),
        borderRadius: BorderRadius.circular(DiscoverTokens.pill),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: DiscoverTokens.badgeStyle,
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
