import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/discover/domain/discover_feed.dart';
import '../../features/discover/domain/discover_story.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// The full-width modules that break up the product grid (DISCOVER §9).
///
/// Each one has exactly ONE primary action (§26.6). The Giveaway module in
/// particular gets a single `View Giveaway` and nothing else — §9.2 says so
/// explicitly, because a second CTA there competes with the giveaway itself.

/// `COMPLETE YOUR LOOK` (§9.1) — the retention module.
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
    // as a sentence ("Your tops") rather than "Your ".
    final anchorName = (item.anchor.title ?? item.anchor.category ?? '').trim();

    return _ModuleShell(
      semanticLabel: '${l10n.wtmShopCompleteLook}. $anchorName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EyebrowLabel(l10n.wtmShopCompleteLook),
          const SizedBox(height: WtmSpace.s8),
          Text(
            l10n.wtmShopCompleteLookWith(anchorName),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WtmType.h2.copyWith(fontSize: 17, height: 1.2),
          ),
          const SizedBox(height: WtmSpace.s12),
          SizedBox(
            height: 92,
            child: Row(
              children: [
                // The owned piece leads, visually distinct from the suggestions.
                _Thumb(
                  url: item.anchor.cutoutUrl ?? item.anchor.imageUrl,
                  highlighted: true,
                ),
                const SizedBox(width: WtmSpace.s8),
                Text('+', style: WtmType.h2.copyWith(color: WtmColors.gold)),
                const SizedBox(width: WtmSpace.s8),
                for (final product in item.suggestions) ...[
                  _Thumb(url: product.imageUrl),
                  const SizedBox(width: WtmSpace.s8),
                ],
              ],
            ),
          ),
          const SizedBox(height: WtmSpace.s12),
          GradientCta(label: l10n.wtmShopCompleteLookCta, onPressed: onCta),
        ],
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
    return _ModuleShell(
      semanticLabel: [story.category, story.title, ?story.subtitle].join('. '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (story.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(WtmRadius.tile),
              child: AspectRatio(
                aspectRatio: 2.1,
                child: CachedNetworkImage(
                  imageUrl: story.imageUrl!,
                  cacheKey: stableImageCacheKey(story.imageUrl!),
                  fit: BoxFit.cover,
                  memCacheWidth: 900,
                  placeholder: (_, _) =>
                      const AuroraBox(height: double.infinity, vignette: true),
                  errorWidget: (_, _, _) =>
                      const AuroraBox(height: double.infinity, vignette: true),
                ),
              ),
            ),
            const SizedBox(height: WtmSpace.s12),
          ],
          EyebrowLabel(story.category),
          const SizedBox(height: WtmSpace.s6),
          Text(
            story.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WtmType.h2.copyWith(fontSize: 17, height: 1.2),
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
          const SizedBox(height: WtmSpace.s12),
          // ONE action. §9.2 forbids a second CTA on the feed card.
          GradientCta(label: ctaLabel, onPressed: onCta),
        ],
      ),
    );
  }
}

/// Shared module chrome: full width, premium corners, one subtle border, no
/// glow. Glow is reserved for fresh stories and AI actions (§25).
class _ModuleShell extends StatelessWidget {
  const _ModuleShell({required this.child, required this.semanticLabel});

  final Widget child;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(WtmSpace.s14),
        decoration: BoxDecoration(
          gradient: WtmGradients.cardFill,
          borderRadius: BorderRadius.circular(WtmRadius.card),
          border: Border.all(color: WtmColors.line),
        ),
        child: child,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, this.highlighted = false});

  final String? url;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WtmRadius.tile),
        border: Border.all(
          color: highlighted ? WtmColors.pillBorder : WtmColors.line,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WtmRadius.tile - 1),
        child: url == null || url!.isEmpty
            ? const AuroraBox(height: double.infinity)
            : CachedNetworkImage(
                imageUrl: url!,
                cacheKey: stableImageCacheKey(url!),
                fit: BoxFit.cover,
                memCacheWidth: 210,
                placeholder: (_, _) => const AuroraBox(height: double.infinity),
                errorWidget: (_, _, _) =>
                    const AuroraBox(height: double.infinity),
              ),
      ),
    );
  }
}
