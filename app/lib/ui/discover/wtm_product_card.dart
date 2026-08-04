import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/product.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// Localized copy for a typed [MatchReason] (DISCOVER spec §37.2).
///
/// The server sends a CODE and the app renders the sentence, which is the only
/// way this reads correctly in a second language. [MatchReason.unknown] — a
/// code from a newer backend — deliberately yields null: no reason at all is
/// better than a placeholder the user cannot act on (§37.4).
String? matchReasonLabel(AppLocalizations l10n, MatchReason? reason) =>
    switch (reason) {
      MatchReason.closetMatch => l10n.wtmShopReasonCloset,
      MatchReason.moodMatch => l10n.wtmShopReasonMood,
      MatchReason.styleMatch => l10n.wtmShopReasonStyle,
      MatchReason.budgetFit => l10n.wtmShopReasonBudget,
      MatchReason.colorMatch => l10n.wtmShopReasonColor,
      MatchReason.trending => l10n.wtmShopReasonTrending,
      MatchReason.newArrival => l10n.wtmShopReasonNew,
      MatchReason.priceDrop => l10n.wtmShopReasonPriceDrop,
      MatchReason.curated => l10n.wtmShopReasonCurated,
      MatchReason.unknown || null => null,
    };

/// A product card in the Discover grid (§8.1).
///
/// What is on it: image, merchant, title (two lines), price, optional original
/// price, ONE match reason, a save heart, and a Try On badge when the product
/// is genuinely compatible.
///
/// What is deliberately NOT on it: the description, every size, every colour,
/// delivery details, merchant ratings, a second CTA, or a second status badge.
/// §8.1 lists those as exclusions and §26 makes it a rule — a card that tries
/// to be a product page is what turns a feed into a marketplace.
class WtmProductCard extends StatelessWidget {
  const WtmProductCard({
    super.key,
    required this.product,
    required this.onToggleSave,
    this.onTap,
    this.onTryOn,
  });

  final Product product;
  final VoidCallback onToggleSave;

  /// Product Details is Phase 4. Until it exists this is null and the card
  /// carries no tap affordance, rather than pointing at a screen that is not
  /// there yet.
  final VoidCallback? onTap;

  /// Shopping try-on is Phase 5; null until then.
  final VoidCallback? onTryOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = matchReasonLabel(l10n, product.matchReason);
    final discount = product.discountPercent;

    // ONE status badge, chosen by severity: being unable to buy something
    // matters more than it being cheap (§26.11 — no cramped badge stacking).
    final String? badge;
    if (product.isOutOfStock) {
      badge = l10n.wtmShopSoldOut;
    } else if (product.stockStatus == StockStatus.lowStock) {
      badge = l10n.wtmShopLowStock;
    } else if (discount != null) {
      badge = l10n.wtmShopDiscountOff(discount);
    } else {
      badge = null;
    }

    return Semantics(
      button: onTap != null,
      label: [
        product.brand ?? product.merchant.name,
        product.title,
        product.price.format(locale: l10n.localeName),
        ?reason,
        ?badge,
        if (product.sponsored) l10n.wtmShopSponsored,
      ].join('. '),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // A FIXED aspect ratio, so the grid does not reflow as images
              // arrive at different sizes (§23 "fixed image aspect ratios").
              AspectRatio(
                aspectRatio: 0.74,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(WtmRadius.tile),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Image(product: product),
                      if (badge != null)
                        Positioned(
                          left: WtmSpace.s6,
                          top: WtmSpace.s6,
                          child: _Pill(
                            label: badge,
                            muted: product.isOutOfStock,
                          ),
                        ),
                      Positioned(
                        right: WtmSpace.s4,
                        top: WtmSpace.s4,
                        child: _SaveButton(
                          saved: product.saved,
                          onTap: onToggleSave,
                        ),
                      ),
                      if (product.isTryOnReady && onTryOn != null)
                        Positioned(
                          right: WtmSpace.s6,
                          bottom: WtmSpace.s6,
                          child: GestureDetector(
                            onTap: onTryOn,
                            child: _Pill(
                              label: l10n.wtmShopTryOn,
                              accent: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WtmSpace.s8),
              Text(
                (product.brand ?? product.merchant.name).toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WtmType.micro.copyWith(
                  fontSize: 8,
                  letterSpacing: 0.9,
                  color: WtmColors.gold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.title,
                // Two lines maximum (§8.1, §25).
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WtmType.body.copyWith(fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: WtmSpace.s4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      product.price.format(locale: l10n.localeName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WtmType.labelMedium.copyWith(fontSize: 13),
                    ),
                  ),
                  if (product.isDiscounted) ...[
                    const SizedBox(width: WtmSpace.s6),
                    Flexible(
                      child: Text(
                        product.originalPrice!.format(locale: l10n.localeName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WtmType.micro.copyWith(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Exactly one reason, or none (§8.1, anti-clutter rule 7).
              if (reason != null) ...[
                const SizedBox(height: 2),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WtmType.micro.copyWith(fontSize: 9),
                ),
              ],
              // Sponsored placements must be labelled and must never read as an
              // organic personalized match (§39).
              if (product.sponsored) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.wtmShopSponsored,
                  style: WtmType.micro.copyWith(
                    fontSize: 8,
                    color: WtmColors.faint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final url = product.imageUrl;
    if (url == null) {
      return const AuroraBox(height: double.infinity, vignette: true);
    }
    return ColorFiltered(
      // A sold-out product is desaturated rather than hidden: it still tells
      // the user something, and hiding it silently would look like a bug.
      colorFilter: product.isOutOfStock
          ? const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0, 0, 0, 0.6, 0,
            ])
          : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
      child: CachedNetworkImage(
        imageUrl: url,
        cacheKey: stableImageCacheKey(url),
        fit: BoxFit.cover,
        // Honour the merchant's focal point so a portrait crop does not cut a
        // face or a hemline (§6.2, §27, §35).
        alignment: Alignment(
          product.imageFocalX * 2 - 1,
          product.imageFocalY * 2 - 1,
        ),
        // Decode at card size, not full resolution (§23).
        memCacheWidth: 500,
        placeholder: (_, _) =>
            const AuroraBox(height: double.infinity, vignette: true),
        errorWidget: (_, _, _) =>
            const AuroraBox(height: double.infinity, vignette: true),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.accent = false, this.muted = false});

  final String label;
  final bool accent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WtmSpace.s6, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? WtmColors.pillBg : const Color(0xB305030A),
        border: Border.all(
          color: accent ? WtmColors.pillBorder : WtmColors.line,
        ),
        borderRadius: BorderRadius.circular(WtmRadius.chip),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: WtmType.micro.copyWith(
          fontSize: 8,
          letterSpacing: 0.7,
          color: muted
              ? WtmColors.faint
              : (accent ? WtmColors.gold : WtmColors.text),
        ),
      ),
    );
  }
}

/// The heart. A 44pt hit area around a small glyph so the touch target clears
/// the accessibility minimum without a heavy control sitting on the artwork.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? l10n.wtmShopSaved : l10n.wtmShopSave,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: WtmIcon(
                WtmGlyph.heart,
                size: 16,
                color: saved ? WtmColors.gold : WtmColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
