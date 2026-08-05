import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/router/routes.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/models/product.dart';
import '../../data/repositories/discover_repository.dart';
import '../../features/discover/application/product_details.dart';
import '../../features/discover/application/saved_products.dart';
import '../../features/discover/application/shopping_tryon.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/utils/uuid.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../community/wtm_community_shared.dart';
import '../widgets/widgets.dart';
import 'wtm_product_card.dart';

/// Product Details (DISCOVER §12).
///
/// Two things make this screen different from a card:
///
/// * **It revalidates.** The feed's copy of a price can be minutes old and, from
///   the offline cache, days old. This is where someone decides to spend money,
///   so price, stock and variant availability are re-read on open and the
///   screen says when the source last confirmed them (§12.15, §35).
///
/// * **It is the only place an outbound link is created.** The app holds no
///   retailer URL until the moment of the tap, when the backend records the
///   click and returns ONE destination it has already validated against the
///   merchant's domain allow-list (§18, §38).
///
/// The product passed in `extra` is used only to paint immediately. Everything
/// the user acts on comes from the fresh response.
class WtmProductDetailsScreen extends ConsumerStatefulWidget {
  const WtmProductDetailsScreen({
    super.key,
    required this.productId,
    this.initial,
    this.placement,
  });

  final String productId;

  /// The feed's copy, for an instant first paint. Never the source of a price
  /// the user acts on.
  final Product? initial;

  /// Where the user came from, carried into the click record (§22).
  final String? placement;

  @override
  ConsumerState<WtmProductDetailsScreen> createState() =>
      _WtmProductDetailsScreenState();
}

class _WtmProductDetailsScreenState
    extends ConsumerState<WtmProductDetailsScreen> {
  /// One key per screen instance, so a retry after a dropped response replays
  /// the SAME click rather than logging a second one. Regenerated only after a
  /// click actually completes (§9, §37.3).
  String _clickKey = uuidV4();
  bool _opening = false;
  ShopFailure? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.productOpen,
            properties: {
              DiscoverAnalyticsProps.productId: widget.productId,
              if (widget.placement != null)
                DiscoverAnalyticsProps.feedPlacement: widget.placement!,
            },
          );
      _record('open');
    });
  }

  /// A behavioural signal, fire-and-forget. Never surfaced to the user: a lost
  /// ranking write is not something someone reading a product page can act on.
  void _record(String eventType) {
    ref
        .read(discoverRepositoryProvider)
        .recordInteraction(
          eventType: eventType,
          productId: widget.productId,
          feedPlacement: 'product_details',
          clientEventId: '$eventType:${widget.productId}:$_clickKey',
        )
        .catchError((Object _) {});
  }

  Future<void> _toggleSave(Product product) async {
    try {
      final saved = await ref
          .read(savedOverridesProvider.notifier)
          .toggle(product);
      _record(saved ? 'save' : 'unsave');
      ref
          .read(analyticsProvider)
          .track(
            saved ? AnalyticsEvents.productSave : AnalyticsEvents.productUnsave,
            properties: {DiscoverAnalyticsProps.productId: product.id},
          );
    } catch (_) {
      if (!mounted) return;
      wtmSnack(context, AppLocalizations.of(context).errorGenericTitle);
    }
  }

  /// Creates the tracked click, then hands the ONE returned URL to the
  /// platform browser (§18).
  ///
  /// Every failure keeps the user here. An empty browser tab is the one outcome
  /// worth going out of the way to avoid: it looks like the app broke and it
  /// leaves nothing to do next (§24).
  Future<void> _shop(Product product) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failure = null;
    });

    try {
      final click = await ref
          .read(discoverRepositoryProvider)
          .click(
            product.id,
            idempotencyKey: _clickKey,
            feedPlacement: 'product_details',
            trackingToken: product.trackingToken,
          );
      final opened = await ref.read(linkLauncherProvider).open(click.url);
      if (!mounted) return;

      if (!opened) {
        // The destination was valid but no browser took it. Same user-facing
        // outcome as an unreachable store, and the same recovery.
        setState(() => _failure = ShopFailure.unreachable);
        return;
      }
      ref
          .read(analyticsProvider)
          .track(
            AnalyticsEvents.affiliateClick,
            properties: {
              DiscoverAnalyticsProps.productId: product.id,
              DiscoverAnalyticsProps.merchantId: click.merchant.id,
              DiscoverAnalyticsProps.feedPlacement: 'product_details',
              // Whether a try-on preceded the click — the conversion metric the
              // shopping funnel turns on. Server-derived, never asserted here.
              DiscoverAnalyticsProps.tryOnCompleted: click.tryOnCompleted,
              if (product.trackingToken != null)
                DiscoverAnalyticsProps.trackingToken: product.trackingToken!,
            },
          );
      // The click landed, so the next tap is a NEW action and must not replay
      // this one's stored response.
      _clickKey = uuidV4();
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = shopFailureFor(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// The §36 "report incorrect product information" control. One tap, no form:
  /// the useful signal is WHICH listing is wrong, and asking for an essay
  /// before accepting that would mean fewer reports, not better ones.
  Future<void> _report() async {
    _record('report_info');
    ref
        .read(analyticsProvider)
        .track(
          AnalyticsEvents.productFeedback,
          properties: {
            DiscoverAnalyticsProps.productId: widget.productId,
            DiscoverAnalyticsProps.feedPlacement: 'product_details',
          },
        );
    if (!mounted) return;
    wtmSnack(context, AppLocalizations.of(context).wtmShopReportThanks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(productDetailProvider(widget.productId));
    // The fresh product wins the moment it arrives; `initial` only fills the
    // gap so the screen is never blank (§24).
    final product = detail.asData?.value.product ?? widget.initial;

    return WtmPage(
      title: product?.title ?? l10n.wtmShopProductTitle,
      eyebrow: product?.brand ?? product?.merchant.name,
      trailing: product == null
          ? null
          : _SaveAction(
              saved: watchSaved(ref, product),
              onTap: () => _toggleSave(product),
            ),
      footer: product == null ? null : _actions(l10n, detail, product),
      children: detail.when(
        skipLoadingOnReload: true,
        loading: () =>
            _body(l10n, product: widget.initial, detail: null, loading: true),
        error: (_, _) => widget.initial == null
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmErrorState(
                  title: l10n.wtmShopDetailErrorTitle,
                  message: l10n.errorGenericTitle,
                  retryLabel: l10n.commonRetry,
                  onRetry: () =>
                      ref.invalidate(productDetailProvider(widget.productId)),
                ),
              ]
            // There IS something to show — the card the user tapped. Keep it,
            // and be explicit that it could not be refreshed, rather than
            // replacing a usable page with an error (§24).
            : _body(
                l10n,
                product: widget.initial,
                detail: null,
                staleNote: l10n.wtmShopRefreshFailed,
              ),
        data: (data) => _body(l10n, product: data.product, detail: data),
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l10n, {
    required Product? product,
    required ProductDetail? detail,
    bool loading = false,
    String? staleNote,
  }) {
    if (product == null) {
      return const [LoadingShimmer(width: double.infinity, height: 320)];
    }

    final unavailable = detail != null && !detail.servable;
    final variants = product.variants;

    return [
      // 1. Gallery.
      _Gallery(product: product, dimmed: unavailable),
      const SizedBox(height: WtmSpace.s16),

      // 2–4. Merchant, title, price.
      Text(
        (product.brand ?? product.merchant.name).toUpperCase(),
        style: WtmType.micro.copyWith(
          fontSize: 9,
          letterSpacing: 1.1,
          color: WtmColors.gold,
        ),
      ),
      const SizedBox(height: WtmSpace.s6),
      Text(product.title, style: WtmType.h2),
      const SizedBox(height: WtmSpace.s8),
      _Price(product: product),

      // A product that is gone says so at the top, with alternatives below —
      // not a 404 and not a silent disappearance (§11.3, §24).
      if (unavailable) ...[
        const SizedBox(height: WtmSpace.s12),
        _Note(
          glyph: WtmGlyph.shield,
          title: l10n.wtmShopUnavailableTitle,
          message: l10n.wtmShopUnavailableMessage,
        ),
      ],
      // 15. A price the source has not reconfirmed recently is qualified, never
      // stated flatly (§12.15, §35).
      if (staleNote != null) ...[
        const SizedBox(height: WtmSpace.s12),
        Text(staleNote, style: WtmType.micro),
      ] else if (detail != null &&
          detail.stale &&
          product.lastSyncedAt != null) ...[
        const SizedBox(height: WtmSpace.s12),
        Text(
          l10n.wtmShopStaleNotice(wtmPostTime(l10n, product.lastSyncedAt!)),
          style: WtmType.micro,
        ),
      ],

      // 5–6. Sizes and colours.
      if (product.sizes.isNotEmpty)
        ..._chips(l10n.wtmShopSizesHeading, product.sizes),
      if (product.colors.isNotEmpty)
        ..._chips(l10n.wtmShopColorsHeading, product.colors),

      // 16. Variant-level availability: "has size M" and "size M is in stock in
      // black" are different claims, and only the second is safe to act on.
      if (variants.isNotEmpty) ...[
        const SizedBox(height: WtmSpace.s16),
        EyebrowLabel(l10n.wtmShopAvailabilityHeading),
        const SizedBox(height: WtmSpace.s8),
        WtmChipRow(
          children: [
            for (final variant in variants)
              WtmChip(
                label: [
                  ?variant.size,
                  ?variant.color,
                  if (!variant.isBuyable) l10n.wtmShopVariantSoldOut,
                ].join(' · '),
                on: false,
              ),
          ],
        ),
      ],

      // 7. Try-on compatibility. Now a real destination (§13); the action
      // itself lives in the sticky bar, so this is the statement of fact that
      // explains why the bar has three buttons instead of two.
      if (product.isTryOnReady) ...[
        const SizedBox(height: WtmSpace.s16),
        Row(
          children: [
            const WtmIcon(WtmGlyph.sparkle, size: 13, color: WtmColors.gold),
            const SizedBox(width: WtmSpace.s6),
            Expanded(child: Text(l10n.wtmShopTryOnReady, style: WtmType.micro)),
          ],
        ),
      ],

      // 8. The one personal reason, if there is one.
      if (matchReasonLabel(l10n, product.matchReason) case final reason?) ...[
        const SizedBox(height: WtmSpace.s12),
        Text(reason, style: WtmType.micro.copyWith(color: WtmColors.gold)),
      ],

      // 9. Description.
      if ((product.description ?? '').trim().isNotEmpty) ...[
        const SizedBox(height: WtmSpace.s16),
        EyebrowLabel(l10n.wtmShopDescriptionHeading),
        const SizedBox(height: WtmSpace.s8),
        Text(product.description!, style: WtmType.body.copyWith(fontSize: 14)),
      ],

      // 10. Delivery region — from the merchant's declared shipping list, never
      // guessed (§12.10, §34).
      const SizedBox(height: WtmSpace.s16),
      EyebrowLabel(l10n.wtmShopDeliveryHeading),
      const SizedBox(height: WtmSpace.s8),
      Text(
        (detail?.deliveryCountries.isNotEmpty ?? false)
            ? detail!.deliveryCountries.join(' · ')
            : l10n.wtmShopDeliveryUnlisted,
        style: WtmType.micro,
      ),

      // 11. Affiliate disclosure — mandatory, and never buried under a fold
      // the user has to hunt for (§12.11).
      const SizedBox(height: WtmSpace.s16),
      Text(
        l10n.wtmShopDisclosure,
        style: WtmType.micro.copyWith(color: WtmColors.muted),
      ),

      const SizedBox(height: WtmSpace.s12),
      GhostButton(label: l10n.wtmShopReportInfo, onPressed: _report),

      // 12. Similar products.
      const SizedBox(height: WtmSpace.s22),
      _Similar(productId: widget.productId, placement: widget.placement),

      if (loading) ...[
        const SizedBox(height: WtmSpace.s16),
        const LoadingShimmer(width: double.infinity, height: 60),
      ],
      const SizedBox(height: WtmSpace.s22),
    ];
  }

  List<Widget> _chips(String heading, List<String> values) => [
    const SizedBox(height: WtmSpace.s16),
    EyebrowLabel(heading),
    const SizedBox(height: WtmSpace.s8),
    WtmChipRow(
      children: [for (final value in values) WtmChip(label: value, on: false)],
    ),
  ];

  /// Sends this product into the existing MoodMirror pipeline (§13).
  ///
  /// Never a dead tap: a product whose compatibility has not actually passed,
  /// or that has no usable image, says so instead of opening a flow that would
  /// fail later (§35).
  void _tryOn(Product product) {
    final started = startShoppingTryOn(
      context,
      ref,
      product,
      placement: widget.placement ?? 'product_details',
    );
    if (!started) {
      wtmSnack(context, AppLocalizations.of(context).wtmShopTryOnUnavailable);
    }
  }

  /// 14. The sticky action bar.
  ///
  /// §12's two pairings: `[ Try On ] [ Shop at Store ]` for a verified
  /// try-on-ready product, `[ Save ] [ Shop at Store ]` otherwise. Save keeps
  /// its place in the header heart either way, so nothing is lost when Try On
  /// takes the slot. The store action is disabled outright when the server says
  /// no click can be produced, so a tap cannot fail for a reason the user could
  /// have been told about first.
  Widget _actions(
    AppLocalizations l10n,
    AsyncValue<ProductDetail> detail,
    Product product,
  ) {
    final data = detail.asData?.value;
    final canShop = data == null || data.shoppable;
    final saved = watchSaved(ref, product);
    // Only a product the SERVER still calls servable can be tried on: paying
    // credits to render something that has sold out would be the worst
    // possible use of them.
    final canTryOn = product.isTryOnReady && (data?.servable ?? true);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_failure != null) ...[
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  _failure == ShopFailure.unavailable
                      ? l10n.wtmShopUnavailableTitle
                      : l10n.wtmShopStoreUnreachable,
                  style: WtmType.micro.copyWith(color: WtmColors.text),
                ),
              ),
              // Retry only where retrying can work. A product that is gone
              // will not come back by tapping again (§24).
              //
              // Both children are Expanded because GhostButton stretches to
              // `double.infinity`, and an unbounded Row slot turns that into
              // an infinite-width layout error rather than a wide button.
              if (_failure == ShopFailure.unreachable) ...[
                const SizedBox(width: WtmSpace.s10),
                Expanded(
                  flex: 2,
                  child: GhostButton(
                    label: l10n.commonRetry,
                    onPressed: () => _shop(product),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: WtmSpace.s10),
        ],
        Row(
          children: [
            Expanded(
              child: canTryOn
                  ? GhostButton(
                      label: l10n.wtmShopTryOnThis,
                      foregroundColor: WtmColors.gold,
                      onPressed: () => _tryOn(product),
                    )
                  : GhostButton(
                      label: saved ? l10n.wtmShopSaved : l10n.wtmShopSave,
                      foregroundColor: saved ? WtmColors.gold : WtmColors.text,
                      onPressed: () => _toggleSave(product),
                    ),
            ),
            const SizedBox(width: WtmSpace.s10),
            Expanded(
              flex: 2,
              child: GradientCta(
                label: _opening
                    ? l10n.wtmShopOpeningStore
                    : l10n.wtmShopShopAtStore,
                onPressed: (_opening || !canShop) ? null : () => _shop(product),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 1. The gallery. Fixed aspect ratio so the page does not reflow as images
/// arrive, and one page dot per image rather than a nested carousel (§26.12).
class _Gallery extends StatefulWidget {
  const _Gallery({required this.product, this.dimmed = false});

  final Product product;
  final bool dimmed;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.product.imageUrls;
    if (images.isEmpty) {
      return const AspectRatio(
        aspectRatio: 0.82,
        child: AuroraBox(height: double.infinity, vignette: true),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 0.82,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WtmRadius.card),
            child: PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Opacity(
                // A product that is gone is dimmed rather than hidden: it
                // still tells the user something.
                opacity: widget.dimmed ? 0.45 : 1,
                child: CachedNetworkImage(
                  imageUrl: images[i],
                  cacheKey: stableImageCacheKey(images[i]),
                  fit: BoxFit.cover,
                  alignment: Alignment(
                    widget.product.imageFocalX * 2 - 1,
                    widget.product.imageFocalY * 2 - 1,
                  ),
                  memCacheWidth: 900,
                  placeholder: (_, _) =>
                      const AuroraBox(height: double.infinity, vignette: true),
                  errorWidget: (_, _, _) =>
                      const AuroraBox(height: double.infinity, vignette: true),
                ),
              ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: WtmSpace.s10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++) ...[
                if (i > 0) const SizedBox(width: WtmSpace.s6),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index ? WtmColors.gold : WtmColors.line,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            product.price.format(locale: l10n.localeName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WtmType.labelMedium.copyWith(fontSize: 17),
          ),
        ),
        // Only a genuine, same-currency reduction is ever shown as one.
        if (product.isDiscounted) ...[
          const SizedBox(width: WtmSpace.s8),
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
          const SizedBox(width: WtmSpace.s8),
          Text(
            l10n.wtmShopDiscountOff(product.discountPercent!),
            style: WtmType.micro.copyWith(color: WtmColors.gold),
          ),
        ],
      ],
    );
  }
}

/// The product card's image ratio. Mirrored here because the similar rail has
/// to reserve height for a card it does not lay out itself.
const _cardAspect = 0.74;

/// 12. Alternatives. Its own async section, so a failure here shows nothing
/// rather than taking the product off the screen.
class _Similar extends ConsumerWidget {
  const _Similar({required this.productId, this.placement});

  final String productId;
  final String? placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final similar = ref.watch(similarProductsProvider(productId));
    final items = similar.asData?.value ?? const <Product>[];

    if (similar.isLoading) {
      return const LoadingShimmer(width: double.infinity, height: 180);
    }
    if (items.isEmpty) return const SizedBox.shrink();

    // A horizontal list needs a bounded height, but a hard-coded one clips the
    // card on a small phone or at a large text scale — the "no product-card
    // overflow" criterion in §31. So it is DERIVED: the image is a fixed ratio
    // of the card width, and the text block below it grows with the user's
    // font scale.
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = (width * 0.42).clamp(140.0, 190.0);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final railHeight = cardWidth / _cardAspect + 112 * textScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EyebrowLabel(l10n.wtmShopSimilarHeading),
        const SizedBox(height: WtmSpace.s12),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: WtmSpace.s10),
            itemBuilder: (context, i) {
              final product = items[i];
              return SizedBox(
                width: cardWidth,
                child: WtmProductCard(
                  key: ValueKey('similar:${product.id}'),
                  product: product.copyWith(saved: watchSaved(ref, product)),
                  onToggleSave: () => ref
                      .read(savedOverridesProvider.notifier)
                      .toggle(product)
                      .catchError((Object _) => product.saved),
                  // Replaces rather than stacks: pushing details on details
                  // indefinitely would bury the back button under a pile of
                  // near-identical screens.
                  onTap: () => context.pushReplacement(
                    AppRoute.wtmProductPath(product.id),
                    extra: product,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The header heart. Mirrors the sticky bar's Save so the state is the same
/// wherever the user looks.
class _SaveAction extends StatelessWidget {
  const _SaveAction({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return WtmIconButton(
      WtmGlyph.heart,
      semanticLabel: saved ? l10n.wtmShopSaved : l10n.wtmShopSave,
      color: saved ? WtmColors.gold : WtmColors.muted,
      onTap: onTap,
    );
  }
}

/// A quiet inline notice. Never red: a sold-out product is information, not an
/// error (§25).
class _Note extends StatelessWidget {
  const _Note({required this.glyph, required this.title, this.message});

  final WtmGlyph glyph;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WtmSpace.s12),
      decoration: BoxDecoration(
        color: WtmColors.chipBg,
        border: Border.all(color: WtmColors.line),
        borderRadius: BorderRadius.circular(WtmRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WtmIcon(glyph, size: 14, color: WtmColors.muted),
          const SizedBox(width: WtmSpace.s10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WtmType.labelMedium.copyWith(fontSize: 13)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: WtmType.micro),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
