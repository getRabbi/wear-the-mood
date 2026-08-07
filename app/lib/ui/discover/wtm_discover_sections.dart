import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/utils/image_format.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../widgets/widgets.dart';

/// The editorial furniture of the Discover feed: a section heading, the
/// curated product band, and the two full-width story cards.
///
/// Geometry, type and colour come from [DiscoverTokens], extracted 1:1 from
/// the approved prototype. Together these are what turn the feed from a
/// product grid into a magazine: every band is introduced, capped, and
/// separated by something that is not a product.

/// Kicker + serif heading, with an optional text action on the right
/// (prototype `.section-head`).
class WtmSectionHead extends StatelessWidget {
  const WtmSectionHead({
    super.key,
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String eyebrow;
  final String title;

  /// Quiet secondary affordance — "Giveaways", "Newsroom", "View all". It is
  /// navigation, not a second CTA competing with the card's own.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// An arbitrary trailing control, used for the filter indicator. Takes
  /// precedence over [actionLabel].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = DiscoverTokens.padFor(width);
    final action =
        trailing ??
        (actionLabel == null || onAction == null
            ? null
            : WtmTextAction(label: actionLabel!, onTap: onAction!));

    // `.section-head { justify-content: space-between }` — the action belongs on
    // the RIGHT EDGE, not tucked against the end of the heading. It was reading
    // as part of the title on every section: "A quick read Newsroom".
    //
    // Expanded (tight) rather than Flexible (loose) is what does it: the heading
    // column claims the whole remaining row, so the action is pushed out to the
    // margin. The heading still gives way first, because it ellipsises at two
    // lines while the action keeps its intrinsic width.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      // The cap comes from the ROW's own width, not the screen's: the screen
      // width minus the gutters can go negative on a degenerate frame, and a
      // negative maxWidth is a non-normalized constraint, which asserts.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actionMax = constraints.hasBoundedWidth
              ? constraints.maxWidth * 0.45
              : double.infinity;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DiscoverTokens.kicker,
                    ),
                    const SizedBox(height: 7), // .section-kicker margin-bottom
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DiscoverTokens.sectionTitle,
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 14), // .section-head gap
                // A translated label at 2x text could otherwise take the whole
                // row and leave the heading nothing to ellipsise into, so the
                // action is capped at a little under half and ellipsises there.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: actionMax),
                  child: action,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// `.text-action` — lavender, 13px, no box.
class WtmTextAction extends StatelessWidget {
  const WtmTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            // Vertical padding buys the 48dp tap target without a visible box.
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.textActionStyle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Card geometry for the curated product band (`.product-card`).
abstract final class WtmProductStripMetrics {
  static const gap = DiscoverTokens.productGap;

  /// The prototype fixes 178px, dropping to 160px under its 350px breakpoint.
  /// Above phone widths the card is allowed to grow a little so a tablet shows
  /// more cards without leaving a dead gutter — never into a banner.
  static double widthFor(double viewportWidth) {
    if (viewportWidth <= DiscoverTokens.narrowBreakpoint) {
      return DiscoverTokens.productWidthNarrow;
    }
    if (viewportWidth < 600) return DiscoverTokens.productWidth;
    return (viewportWidth / 4.2).clamp(DiscoverTokens.productWidth, 214.0);
  }
}

/// A horizontally scrolled band of product cards (prototype `.product-strip`).
///
/// A [SingleChildScrollView] rather than a horizontal [ListView]: the band is
/// capped at four cards, so nothing is gained by lazy building, and this way
/// the band takes its HEIGHT from the tallest card instead of a guessed
/// constant — which is what keeps it from overflowing at 2x text scale.
class WtmProductStrip extends StatelessWidget {
  const WtmProductStrip({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = WtmProductStripMetrics.widthFor(width);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        DiscoverTokens.padFor(width),
        2,
        DiscoverTokens.padFor(width),
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: WtmProductStripMetrics.gap),
            SizedBox(width: cardWidth, child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// The tall editorial campaign card — Giveaway, or an Offer when no giveaway
/// is live (prototype `.feature-card`).
///
/// One action, and the whole card carries it: a second competing button on a
/// giveaway card is exactly what the layout rules forbid.
class WtmFeatureCard extends StatelessWidget {
  const WtmFeatureCard({
    super.key,
    required this.label,
    required this.title,
    required this.actionLabel,
    required this.onTap,
    this.meta,
    this.imageUrl,
  });

  /// `.feature-label` — the kicker inside the card, e.g. `GIVEAWAY`.
  final String label;
  final String title;

  /// One honest supporting line — a real end date, a real discount. Never an
  /// invented countdown.
  final String? meta;
  final String? imageUrl;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Grows with the user's text size instead of clipping copy at 2x.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final minHeight = (DiscoverTokens.featureMinHeight * scale).clamp(
      DiscoverTokens.featureMinHeight,
      360.0,
    );

    return Semantics(
      button: true,
      label: [label, title, ?meta, actionLabel].join('. '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DiscoverTokens.radiusXl),
              border: Border.all(color: DiscoverTokens.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DiscoverTokens.radiusXl - 1),
              // Bottom-left, so the copy sits on the scrim exactly as the
              // approved card does. The unpositioned copy column is what gives
              // the Stack its height, which is why there is no Spacer here —
              // inside a scrolling list the incoming height is unbounded and a
              // flex child would have nothing to expand into.
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Positioned.fill(child: _FeatureArtwork(url: imageUrl)),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: DiscoverTokens.featureScrim,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(
                      DiscoverTokens.featurePadding,
                    ),
                    child: FractionallySizedBox(
                      // `.feature-content { max-width: 78% }` — the copy never
                      // runs the full width of the artwork.
                      widthFactor: 0.78,
                      alignment: Alignment.bottomLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DiscoverTokens.featureLabelStyle,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DiscoverTokens.featureTitle,
                          ),
                          if (meta != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DiscoverTokens.featureMetaStyle,
                            ),
                          ],
                          const SizedBox(height: 14),
                          // ONE action, as an inline affordance rather than a
                          // filled button: the whole card is the tap target,
                          // and a second gradient here would fight the CTA
                          // language reserved for AI actions.
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  actionLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DiscoverTokens.featureAction,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                '→',
                                style: DiscoverTokens.featureAction,
                              ),
                            ],
                          ),
                        ],
                      ),
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

/// The split art/copy Newsroom card (prototype `.editorial`).
///
/// Visual-first and deliberately short: never a paragraph of the article in
/// the feed.
class WtmEditorialCard extends StatelessWidget {
  const WtmEditorialCard({
    super.key,
    required this.label,
    required this.title,
    required this.actionLabel,
    required this.onTap,
    this.meta,
    this.imageUrl,
  });

  final String label;
  final String title;
  final String? meta;
  final String? imageUrl;

  /// Spoken, not drawn: the card itself is the action, and a visible button
  /// beside a two-line headline reads as clutter at this size.
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = (DiscoverTokens.editorialMinHeight * scale).clamp(
      DiscoverTokens.editorialMinHeight,
      300.0,
    );

    return Semantics(
      button: true,
      label: [label, title, ?meta, actionLabel].join('. '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: DiscoverTokens.surface,
              borderRadius: BorderRadius.circular(
                DiscoverTokens.radiusEditorial,
              ),
              border: Border.all(color: DiscoverTokens.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                DiscoverTokens.radiusEditorial - 1,
              ),
              // `grid-template-columns: 1.05fr 1fr` — art slightly wider than
              // the copy.
              child: Row(
                children: [
                  Expanded(flex: 105, child: _EditorialArtwork(url: imageUrl)),
                  Expanded(
                    flex: 100,
                    child: Padding(
                      // `.editorial-copy { padding: 17px 15px }`
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 17,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DiscoverTokens.editorialLabel,
                          ),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: DiscoverTokens.editorialTitle,
                            ),
                          ),
                          if (meta != null) ...[
                            const SizedBox(height: 9),
                            Text(
                              meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DiscoverTokens.reason,
                            ),
                          ],
                        ],
                      ),
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

/// `.feature-card` backdrop: the campaign's image where it has one, otherwise
/// the prototype's plum base with its blush and violet glows. A campaign
/// without an image is normal, not an error — it must never leave a hole.
class _FeatureArtwork extends StatelessWidget {
  const _FeatureArtwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: DiscoverTokens.featureBase),
        ),
        DecoratedBox(
          decoration: BoxDecoration(gradient: DiscoverTokens.featureViolet),
        ),
        DecoratedBox(
          decoration: BoxDecoration(gradient: DiscoverTokens.featureBlush),
        ),
      ],
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      cacheKey: stableImageCacheKey(url!),
      fit: BoxFit.cover,
      // Decode at card size, not full resolution.
      memCacheWidth: 900,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// `.editorial-art` — the purple radial with its diagonal wash.
class _EditorialArtwork extends StatelessWidget {
  const _EditorialArtwork({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const fallback = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(gradient: DiscoverTokens.editorialArt),
        ),
        DecoratedBox(
          decoration: BoxDecoration(gradient: DiscoverTokens.editorialWash),
        ),
      ],
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      cacheKey: stableImageCacheKey(url!),
      fit: BoxFit.cover,
      memCacheWidth: 600,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// `.primary-btn` — the prototype's full-width CTA: 100° violet→pink, radius
/// 17, weight-800 plum label.
class WtmPrimaryButton extends StatelessWidget {
  const WtmPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            // 14px vertical padding on a 13px label clears the 48dp floor.
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: DiscoverTokens.primaryCta,
              borderRadius: BorderRadius.circular(DiscoverTokens.radiusCta),
              boxShadow: const [
                // `0 12px 30px rgba(127,85,255,.22)`
                BoxShadow(
                  color: Color(0x387F55FF),
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DiscoverTokens.primaryCtaLabel,
            ),
          ),
        ),
      ),
    );
  }
}

/// `.icon-btn` — 42px rounded-square glass button in the Discover header.
class WtmDiscoverIconButton extends StatelessWidget {
  const WtmDiscoverIconButton({
    super.key,
    required this.glyph,
    required this.semanticLabel,
    required this.onTap,
  });

  final WtmGlyph glyph;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: DiscoverTokens.iconBtn,
            height: DiscoverTokens.iconBtn,
            decoration: BoxDecoration(
              // `background: rgba(255,255,255,.028)`
              color: const Color(0x07FFFFFF),
              borderRadius: BorderRadius.circular(DiscoverTokens.radiusIconBtn),
              border: Border.all(color: DiscoverTokens.line),
            ),
            child: Center(
              child: WtmIcon(glyph, size: 20, color: const Color(0xFFE7DDFF)),
            ),
          ),
        ),
      ),
    );
  }
}
