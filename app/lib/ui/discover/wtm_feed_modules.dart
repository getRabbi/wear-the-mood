import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/discover/domain/discover_feed.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_discover_artwork.dart';
import 'wtm_discover_sections.dart';

/// The full-width modules that break up the product bands (prototype
/// `.look-module`, spec §9).
///
/// Each one has exactly ONE primary action (§26.6). The Giveaway module in
/// particular gets a single `View Giveaway` and nothing else — §9.2 says so
/// explicitly, because a second CTA there competes with the giveaway itself.

/// `COMPLETE YOUR LOOK` (prototype `.look-module`) — the retention module.
///
/// Anchored on a garment the user already owns, with two or three products
/// beside it. Not a shopping banner: the point is what is already in their
/// wardrobe.
class WtmCompleteLookModule extends StatelessWidget {
  const WtmCompleteLookModule({
    super.key,
    required this.item,
    required this.onCta,
  });

  final CompleteLookItem item;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // An untitled garment falls back to its category, so the module still reads
    // as a sentence ("Your tops") rather than "Your ". The composer refuses an
    // anchor that can supply neither.
    final anchorName = (item.anchor.title ?? item.anchor.category ?? '').trim();

    return Semantics(
      container: true,
      label: '${l10n.wtmShopCompleteLook}. $anchorName',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DiscoverTokens.lookPadding),
        decoration: BoxDecoration(
          color: DiscoverTokens.surface,
          borderRadius: BorderRadius.circular(DiscoverTokens.radiusXl),
          border: Border.all(color: DiscoverTokens.line),
        ),
        child: Stack(
          children: [
            // `.look-module` carries a violet glow off its top-right corner.
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  DiscoverTokens.radiusXl - 1,
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: DiscoverTokens.lookAccent,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.wtmShopCompleteLook.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiscoverTokens.kicker,
                ),
                const SizedBox(height: 7),
                Text(
                  l10n.wtmShopCompleteLookWith(anchorName),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DiscoverTokens.sectionTitle,
                ),
                const SizedBox(height: 7),
                Text(
                  l10n.wtmShopCompleteLookSub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DiscoverTokens.lookSub,
                ),
                const SizedBox(height: 15),
                _LookRow(item: item, ownedLabel: l10n.wtmShopInYourCloset),
                const SizedBox(height: 14),
                WtmPrimaryButton(
                  label: l10n.wtmShopCompleteLookCta,
                  onPressed: onCta,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `.look-row` — `grid-template-columns: 1.12fr .86fr .86fr .86fr` with a `+`
/// badge riding the gap between tiles.
class _LookRow extends StatelessWidget {
  const _LookRow({required this.item, required this.ownedLabel});

  final CompleteLookItem item;
  final String ownedLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 112,
          child: _Thumb(
            url: item.anchor.cutoutUrl ?? item.anchor.imageUrl,
            seed: item.anchor.id,
            glyph: wtmGarmentGlyph(item.anchor.category),
            owned: true,
            ownedLabel: ownedLabel,
          ),
        ),
        for (final product in item.suggestions) ...[
          // The badge sits in the gutter, as the prototype's absolutely
          // positioned `.plus` does.
          const _PlusBadge(),
          Expanded(
            flex: 86,
            child: _Thumb(
              url: product.imageUrl,
              seed: product.id,
              glyph: wtmGarmentGlyph(product.category),
            ),
          ),
        ],
      ],
    );
  }
}

/// `.plus` — an 18px lilac disc between two tiles.
class _PlusBadge extends StatelessWidget {
  const _PlusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.look-row { gap: 8px }`, with the badge centred in it.
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: DiscoverTokens.plusBadge,
      height: DiscoverTokens.plusBadge,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: DiscoverTokens.plusBg,
        shape: BoxShape.circle,
      ),
      child: const Text(
        '+',
        style: TextStyle(
          fontFamily: WtmFonts.sans,
          fontSize: 12,
          height: 1.0,
          fontWeight: FontWeight.w700,
          color: DiscoverTokens.plusText,
        ),
      ),
    );
  }
}

/// A Giveaway / Offer / Newsroom module, rendered from the same [DiscoverStory]
/// the rail uses so there is one source of truth for that content (§9.2–§9.4).
class WtmStoryModule extends StatelessWidget {
  const WtmStoryModule({
    super.key,
    required this.story,
    required this.ctaLabel,
    required this.onCta,
  });

  final DiscoverStory story;
  final String ctaLabel;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: [story.category, story.title, ?story.subtitle].join('. '),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DiscoverTokens.lookPadding),
        decoration: BoxDecoration(
          color: DiscoverTokens.surface,
          borderRadius: BorderRadius.circular(DiscoverTokens.radiusXl),
          border: Border.all(color: DiscoverTokens.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (story.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(DiscoverTokens.radiusLg),
                child: AspectRatio(
                  aspectRatio: 2.1,
                  child: CachedNetworkImage(
                    imageUrl: story.imageUrl!,
                    cacheKey: stableImageCacheKey(story.imageUrl!),
                    fit: BoxFit.cover,
                    memCacheWidth: 900,
                    placeholder: (_, _) => const AuroraBox(
                      height: double.infinity,
                      vignette: true,
                    ),
                    errorWidget: (_, _, _) => const AuroraBox(
                      height: double.infinity,
                      vignette: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WtmSpace.s12),
            ],
            Text(
              story.category.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.kicker,
            ),
            const SizedBox(height: 7),
            Text(
              story.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.sectionTitle,
            ),
            if (story.subtitle != null) ...[
              const SizedBox(height: 7),
              Text(
                story.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DiscoverTokens.lookSub,
              ),
            ],
            const SizedBox(height: 14),
            // ONE action. §9.2 forbids a second CTA on the feed card.
            WtmPrimaryButton(label: ctaLabel, onPressed: onCta),
          ],
        ),
      ),
    );
  }
}

/// `.look-item` — a 4/5 portrait tile, with the owned piece wearing its
/// "IN YOUR CLOSET" chip.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.seed,
    required this.glyph,
    this.owned = false,
    this.ownedLabel = '',
  });

  final String? url;
  final String seed;
  final WtmGlyph glyph;
  final bool owned;
  final String ownedLabel;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: DiscoverTokens.productAspect,
      child: Container(
        decoration: BoxDecoration(
          gradient: DiscoverTokens.lookItemFill,
          borderRadius: BorderRadius.circular(DiscoverTokens.radiusLookItem),
          border: Border.all(
            color: owned ? WtmColors.pillBorder : DiscoverTokens.line,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            DiscoverTokens.radiusLookItem - 1,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The tiles are small and there are four of them side by side, so
              // a failed image must not leave four identical dark squares —
              // each carries its own silhouette instead.
              WtmDiscoverArtwork(
                url: url,
                seed: seed,
                glyph: glyph,
                decodeWidth: 300,
                glyphScale: 0.5,
              ),
              if (owned)
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: DiscoverTokens.ownedChipBg,
                      borderRadius: BorderRadius.circular(DiscoverTokens.pill),
                    ),
                    // The tile is roughly 63dp wide on a phone and the label
                    // is fourteen tracked characters, so at a fixed size it
                    // clipped to "IN YOUR". Scaling down keeps the whole
                    // phrase — a half-word reads as a bug, not a label.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ownedLabel.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: DiscoverTokens.ownedChip,
                      ),
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
