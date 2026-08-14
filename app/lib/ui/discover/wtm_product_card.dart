import 'package:flutter/material.dart';

import '../../data/models/product.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/pressable_scale.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_discover_tokens.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_surface.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';
import 'wtm_discover_artwork.dart';

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

/// A product card (§8.1) — the ONE way a product is drawn, everywhere.
///
/// Discover's two rows, Search, Browse, Saved, the Similar rail and Home's
/// Shop Your Mood preview all render this. That is deliberate and it is the
/// point: `TRY ON` is the action this app exists for, and a per-screen card
/// would mean a per-screen decision about whether to offer it. Here the
/// decision is made once, by the product.
///
/// What is on it: image, merchant, title (two lines), price, optional original
/// price, ONE match reason, a save heart, and `TRY ON` when the product has a
/// garment image the server has cleared.
///
/// Three hit areas, and they do not overlap: the card opens Product Details,
/// the heart saves, the pill starts a try-on.
///
/// What is deliberately NOT on it: the description, every size, every colour,
/// delivery details, merchant ratings, a second CTA, or a second status badge.
/// §8.1 lists those as exclusions and §26 makes it a rule — a card that tries
/// to be a product page is what turns a feed into a marketplace. In particular
/// there is no second Try On beneath the card; the pill on the artwork is it.
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

  /// Opens Product Details. Nullable so a card can be drawn somewhere with
  /// nowhere to go, which is better than an affordance that leads nowhere —
  /// but every surface in the app passes it.
  final VoidCallback? onTap;

  /// Starts a shopping try-on, through the one shared entry point.
  ///
  /// Every surface passes this. A null here does NOT mean "this product cannot
  /// be tried on" — that is [Product.tryOnGarmentImageUrl]'s answer — it means
  /// the surface has no try-on to offer at all, and the pill is withheld
  /// rather than drawn dead.
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
        // Announced so the action is not invisible to a screen reader. The
        // card's own semantics are merged, so this reads as a property of the
        // product rather than a second button — reaching the control itself
        // means opening Product Details, where Try On is the primary action.
        if (product.tryOnGarmentImageUrl != null && onTryOn != null)
          l10n.wtmShopTryOnReady,
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
              // `.product-image` — a FIXED 4/5 portrait, so the band does not
              // reflow as images arrive at different sizes (§23).
              AspectRatio(
                aspectRatio: DiscoverTokens.productAspect,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      DiscoverTokens.radiusLg,
                    ),
                    border: Border.all(color: DiscoverTokens.line),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      DiscoverTokens.radiusLg - 1,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Image(product: product),
                        // `.heart` — glass circle, top right.
                        Positioned(
                          right: 10,
                          top: 10,
                          child: _SaveButton(
                            saved: product.saved,
                            onTap: onToggleSave,
                          ),
                        ),
                        // The bottom band: status capsule on the left, `TRY ON`
                        // on the right.
                        //
                        // ONE row rather than two independent corners. As two
                        // `Positioned` children they overlapped on a narrow
                        // card — a `Stack` lets its children collide silently,
                        // so nothing threw and no test caught it; a discounted
                        // try-on-ready product on Home's three-up preview drew
                        // `30% OFF` straight through `TRY ON`. A row cannot do
                        // that whatever the width.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _BottomBand(
                            badge: badge,
                            muted: product.isOutOfStock,
                            // `TRY ON` is gated on the RESOLVED garment image,
                            // not on the status alone: a ready product with
                            // nothing usable to send would otherwise draw a
                            // pill that apologises on tap, and a dead tap is
                            // worse than no affordance.
                            onTryOn: product.tryOnGarmentImageUrl != null
                                ? onTryOn
                                : null,
                            tryOnLabel: l10n.wtmShopTryOn,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // `.product-info { padding: 10px 3px 0 }`
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (product.brand ?? product.merchant.name).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DiscoverTokens.brand,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      product.title,
                      // Two lines maximum (§8.1, §25).
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: DiscoverTokens.productName,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            product.price.format(locale: l10n.localeName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DiscoverTokens.price,
                          ),
                        ),
                        if (product.isDiscounted) ...[
                          const SizedBox(width: WtmSpace.s6),
                          Flexible(
                            child: Text(
                              product.originalPrice!.format(
                                locale: l10n.localeName,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DiscoverTokens.reason.copyWith(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Exactly one reason, or none (§8.1, anti-clutter rule 7).
                    if (reason != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DiscoverTokens.reason,
                      ),
                    ],
                    // Sponsored placements must be labelled and must never
                    // read as an organic personalized match (§39).
                    if (product.sponsored) ...[
                      const SizedBox(height: 3),
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
    return WtmDiscoverArtwork(
      url: product.imageUrl,
      // Per product, so two cards in the same row never draw the same fallback.
      seed: product.id,
      glyph: wtmGarmentGlyph(product.category),
      // Honour the merchant's focal point so a portrait crop does not cut a
      // face or a hemline (§6.2, §27, §35).
      alignment: Alignment(
        product.imageFocalX * 2 - 1,
        product.imageFocalY * 2 - 1,
      ),
      // A sold-out product is desaturated rather than hidden: it still tells
      // the user something, and hiding it silently would look like a bug.
      colorFilter: product.isOutOfStock
          ? const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0, 0, 0, 0.6, 0,
            ])
          : null,
    );
  }
}

/// The strip along the bottom of the artwork: status capsule, then `TRY ON`.
///
/// Both keep the 10px inset they have always had, and on any card wide enough
/// for both they look exactly as they did side by side. What this adds is what
/// happens when the card is NOT wide enough — Home previews three products
/// across, so its cards are barely a third of the screen and the two capsules
/// wanted the same pixels.
///
/// The action wins and the status capsule is dropped, rather than either
/// truncating to `30%…` or overlapping. The discount is still on the card, in
/// the struck-through price directly beneath; `TRY ON` exists nowhere else.
/// A sold-out or low-stock product is not at risk of losing its label this
/// way — the server does not serve out-of-stock products to the feed at all,
/// and a product that cannot be rendered has no pill to compete with.
class _BottomBand extends StatelessWidget {
  const _BottomBand({
    required this.badge,
    required this.muted,
    required this.onTryOn,
    required this.tryOnLabel,
  });

  final String? badge;
  final bool muted;
  final VoidCallback? onTryOn;
  final String tryOnLabel;

  /// The card width below which the status capsule gives up its place.
  ///
  /// Sits just under [DiscoverTokens.productWidth], so every surface that
  /// draws a full-size card — Discover's rows, Search, Browse, Saved, the
  /// Similar rail — keeps the pair exactly as it shipped. Home's three-up
  /// preview is barely two thirds of that and keeps `TRY ON` alone.
  static const _roomForBoth = DiscoverTokens.productWidth - 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tryOn = onTryOn;
        final showBadge =
            badge != null &&
            (tryOn == null || constraints.maxWidth >= _roomForBoth);

        if (!showBadge && tryOn == null) return const SizedBox.shrink();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Flexible as well as thresholded. The threshold is what keeps the
            // approved pairing on a normal card; this is what guarantees the
            // row cannot overflow anyway when a longer translation, a larger
            // text scale or a different font makes the capsule wider than any
            // constant could have predicted.
            if (showBadge)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _Pill(label: badge!, muted: muted),
                ),
              )
            else
              const SizedBox.shrink(),
            if (tryOn != null)
              _TryOnPill(label: tryOnLabel, onTap: tryOn)
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

/// `.pill` — glass capsule on the artwork. At most one status pill per card.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `.pill { padding: 6px 9px }`
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: DiscoverTokens.productPillBg,
        border: Border.all(color: DiscoverTokens.badgeBorder),
        borderRadius: BorderRadius.circular(DiscoverTokens.pill),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        style: DiscoverTokens.productPill.copyWith(
          color: muted ? WtmColors.faint : DiscoverTokens.text,
        ),
      ),
    );
  }
}

/// `TRY ON` — the same glass capsule as a status pill, in the accent, and
/// tappable.
///
/// It keeps the status pill's DARK scrim rather than the near-transparent gold
/// wash the accent variant used to carry: at 6% opacity the capsule vanished
/// over a pale garment, and the one control on the card that has to be found
/// on any image is the one that cannot afford to be conditional on the image.
/// The gold border and label are what mark it as the action.
///
/// The visible capsule is deliberately small — it sits on somebody's clothes,
/// and §1 rules out a button that covers the garment — so the TAP TARGET is
/// grown around it to the 48dp floor with transparent padding instead. The
/// padding is outside the decoration, so nothing about the drawn pill moves.
class _TryOnPill extends StatelessWidget {
  const _TryOnPill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque, so the padded ring around the capsule takes the tap rather
      // than letting it fall through to the card and open Product Details.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(DiscoverTokens.tryOnTapPadding),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: DiscoverTokens.productPillBg,
            border: Border.all(color: WtmColors.pillBorder),
            borderRadius: BorderRadius.circular(DiscoverTokens.pill),
          ),
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: DiscoverTokens.productPill.copyWith(color: WtmColors.gold),
          ),
        ),
      ),
    );
  }
}

/// `.heart` — a 36px glass circle over the artwork, filling to lilac when
/// saved. The tap target is padded out to the 48dp floor around it, so the
/// control stays visually light without being hard to hit.
class _SaveButton extends StatefulWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _pressed = false;

  void _set(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = widget.saved;
    return Semantics(
      button: true,
      toggled: saved,
      label: saved ? l10n.wtmShopSaved : l10n.wtmShopSave,
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => _set(true),
            onTapUp: (_) => _set(false),
            onTapCancel: () => _set(false),
            child: AnimatedContainer(
              duration: WtmMotion.fast,
              curve: WtmMotion.easing,
              width: DiscoverTokens.heart,
              height: DiscoverTokens.heart,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: saved
                    ? DiscoverTokens.heartSavedBg
                    : (_pressed
                          ? DiscoverTokens.heartPressedBg
                          : DiscoverTokens.heartBg),
                border: Border.all(
                  color: saved
                      ? Colors.transparent
                      : (_pressed
                            ? WtmGlass.overlayBorderPressed
                            : DiscoverTokens.heartBorder),
                ),
                // The puck sits on merchant photography, so it carries its own
                // contact shadow rather than trusting the image behind it.
                boxShadow: WtmGlass.overlayShadow,
              ),
              child: Center(
                child: WtmIcon(
                  WtmGlyph.heart,
                  size: 17,
                  color: saved
                      ? DiscoverTokens.heartSavedIcon
                      : WtmGlass.overlayForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
