import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// The editorial furniture of the Discover feed: a section heading, the
/// curated product band, and the two full-width story cards.
///
/// Together these are what turn the feed from a product grid into a magazine:
/// every band is introduced, capped, and separated by something that is not a
/// product (DISCOVER §8.3, §26.13).

/// Eyebrow + serif heading, with an optional text action on the right
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

  /// Quiet secondary affordance — "All giveaways", "Newsroom", "View all".
  /// It is navigation, not a second CTA competing with the card's own (§26.6).
  final String? actionLabel;
  final VoidCallback? onAction;

  /// An arbitrary trailing control, used for the filter indicator. Takes
  /// precedence over [actionLabel].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final action =
        trailing ??
        (actionLabel == null || onAction == null
            ? null
            : _TextAction(label: actionLabel!, onTap: onAction!));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Flexible, not Expanded + Spacer: the heading is translated and the
          // action label grows with it, so on a 320dp phone at 2x text the
          // heading has to give way rather than push the control off screen.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                EyebrowLabel(eyebrow),
                const SizedBox(height: WtmSpace.s6),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.h2.copyWith(fontSize: 20, height: 1.1),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: WtmSpace.s10), action],
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

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
            padding: const EdgeInsets.symmetric(vertical: WtmSpace.s12),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WtmType.chip.copyWith(color: WtmColors.gold),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card geometry for the curated product band.
///
/// Responsive rather than device-specific, the same way the Story rail sizes
/// itself: roughly two cards plus a peek on a phone, more (never bigger) cards
/// on a tablet (§41).
abstract final class WtmProductStripMetrics {
  static const phoneMinWidth = 148.0;
  static const phoneMaxWidth = 178.0;
  static const tabletMaxWidth = 214.0;
  static const gap = WtmSpace.s12;
  static const tabletBreakpoint = 600.0;

  static double widthFor(double viewportWidth) {
    final isTablet = viewportWidth >= tabletBreakpoint;
    final target = (viewportWidth - WtmSpace.screenH * 2 - gap) / 2.05;
    return target.clamp(
      phoneMinWidth,
      isTablet ? tabletMaxWidth : phoneMaxWidth,
    );
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
    final width = WtmProductStripMetrics.widthFor(
      MediaQuery.sizeOf(context).width,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.screenH),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: WtmProductStripMetrics.gap),
            SizedBox(width: width, child: cards[i]),
          ],
        ],
      ),
    );
  }
}

/// The tall editorial campaign card — Giveaway, or an Offer when no giveaway
/// is live (prototype `.feature-card`, spec §9.2/§9.3).
///
/// One action, and the whole card carries it: a second competing button on a
/// giveaway card is exactly what §9.2 forbids.
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

  /// Small uppercase kicker inside the card, e.g. `GIVEAWAY`.
  final String label;
  final String title;

  /// One honest supporting line — a real end date, a real discount. Never an
  /// invented countdown (§26.10).
  final String? meta;
  final String? imageUrl;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Grows with the user's text size instead of clipping copy at 2x (§41).
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final minHeight = (188.0 * scale).clamp(188.0, 320.0);

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
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WtmRadius.card - 1),
              // Bottom-left, so the copy sits on the scrim exactly as the
              // approved card does. The unpositioned copy column is what gives
              // the Stack its height, which is why there is no Spacer here —
              // inside a scrolling list the incoming height is unbounded and a
              // flex child would have nothing to expand into.
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Positioned.fill(child: _Artwork(url: imageUrl)),
                  // Bottom-up scrim, so the copy stays legible over any
                  // artwork the campaign happens to carry (§6.6, §25).
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xF205030A)],
                          stops: [0.30, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(WtmSpace.s16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.micro.copyWith(
                            fontSize: 9,
                            letterSpacing: 1.8,
                            color: WtmColors.gold,
                          ),
                        ),
                        const SizedBox(height: WtmSpace.s8),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.h1.copyWith(fontSize: 24, height: 1.1),
                        ),
                        if (meta != null) ...[
                          const SizedBox(height: WtmSpace.s6),
                          Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WtmType.micro.copyWith(
                              color: WtmColors.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: WtmSpace.s12),
                        // ONE action, as an inline affordance rather than a
                        // filled button: the whole card is the tap target and
                        // a second gradient here would fight the CTA language
                        // reserved for AI actions (§25).
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                actionLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WtmType.labelMedium,
                              ),
                            ),
                            const SizedBox(width: WtmSpace.s6),
                            const WtmIcon(
                              WtmGlyph.chevron,
                              size: 14,
                              color: WtmColors.gold,
                            ),
                          ],
                        ),
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

/// The split art/copy Newsroom card (prototype `.editorial`, spec §9.4).
///
/// Visual-first and deliberately short: never a paragraph of the article in
/// the feed (§26.14).
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
    final height = (150.0 * scale).clamp(150.0, 280.0);
    final artWidth = MediaQuery.sizeOf(context).width * 0.34;

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
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WtmRadius.card - 1),
              child: Row(
                children: [
                  SizedBox(
                    width: artWidth.clamp(104.0, 200.0),
                    height: double.infinity,
                    child: _Artwork(
                      url: imageUrl,
                      variant: AuroraVariant.blush,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(WtmSpace.s14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WtmType.micro.copyWith(
                              fontSize: 8,
                              letterSpacing: 1.4,
                              color: WtmColors.gold,
                            ),
                          ),
                          const SizedBox(height: WtmSpace.s8),
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: WtmType.h2.copyWith(
                                fontSize: 18,
                                height: 1.15,
                              ),
                            ),
                          ),
                          if (meta != null) ...[
                            const SizedBox(height: WtmSpace.s8),
                            Text(
                              meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WtmType.micro,
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

/// A card's backdrop: its image where it has one, otherwise the aurora
/// artwork. A campaign without an image is normal, not an error — it must
/// never leave a hole (§23 "image error fallback").
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, this.variant = AuroraVariant.noir});

  final String? url;
  final AuroraVariant variant;

  @override
  Widget build(BuildContext context) {
    final fallback = AuroraBox(
      height: double.infinity,
      width: double.infinity,
      vignette: true,
      border: false,
      borderRadius: BorderRadius.zero,
      variant: variant,
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      cacheKey: stableImageCacheKey(url!),
      fit: BoxFit.cover,
      // Decode at card size, not full resolution (§23).
      memCacheWidth: 900,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
