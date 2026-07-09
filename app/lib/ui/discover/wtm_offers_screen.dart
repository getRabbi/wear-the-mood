import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/router/routes.dart';
import '../../data/models/offer.dart';
import '../../data/repositories/offers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/image_format.dart';
import '../../shared/widgets/loading_shimmer.dart';
import '../../theme/wtm_colors.dart';
import '../../theme/wtm_shapes.dart';
import '../../theme/wtm_typography.dart';
import '../widgets/widgets.dart';

/// WTM Offers (board 09, P9) — today's brand offers on [offersProvider]. Tap →
/// the offer detail (`?id=`), the Inbox Drops deep-link target for offers.
class WtmOffersScreen extends ConsumerWidget {
  const WtmOffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(offersProvider);

    return WtmPage(
      title: l10n.wtmOffersTitle,
      eyebrow: l10n.wtmDiscover,
      children: async.when<List<Widget>>(
        skipLoadingOnReload: true,
        loading: () => const [
          LoadingShimmer(width: double.infinity, height: 110),
        ],
        error: (_, _) => [
          WtmErrorState(
            title: l10n.wtmOffersErrorTitle,
            message: l10n.errorGenericTitle,
            retryLabel: l10n.commonRetry,
            onRetry: () => ref.invalidate(offersProvider),
          ),
        ],
        data: (offers) => offers.isEmpty
            ? [
                const SizedBox(height: WtmSpace.s22),
                WtmEmptyState(
                  glyph: WtmGlyph.store,
                  title: l10n.wtmOffersEmptyTitle,
                  message: l10n.wtmOffersEmptyMessage,
                ),
              ]
            : [
                for (final (i, o) in offers.indexed) ...[
                  if (i > 0) const SizedBox(height: WtmSpace.s10),
                  _OfferCard(offer: o),
                ],
              ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${offer.brand ?? offer.title} ${offer.discountLabel ?? ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              context.push('${AppRoute.wtmOfferDetail}?id=${offer.id}'),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: WtmGradients.cardFill,
              borderRadius: BorderRadius.circular(WtmRadius.card),
              border: Border.all(color: WtmColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (offer.brand ?? offer.title).toUpperCase(),
                        style: WtmType.h2.copyWith(
                          fontSize: 15,
                          letterSpacing: 4.8,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((offer.discountLabel ?? '').isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(offer.discountLabel!,
                            style: WtmType.goldItalic(
                                WtmType.h2.copyWith(fontSize: 20))),
                      ],
                      const SizedBox(height: 3),
                      Text(offer.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WtmType.micro),
                    ],
                  ),
                ),
                const SizedBox(width: WtmSpace.s12),
                SizedBox(
                  width: 74,
                  height: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(WtmRadius.tile),
                    child: offer.imageUrl == null
                        ? const AuroraBox()
                        : CachedNetworkImage(
                            imageUrl: offer.imageUrl!,
                            cacheKey: stableImageCacheKey(offer.imageUrl!),
                            fit: BoxFit.cover,
                            placeholder: (_, _) => const AuroraBox(),
                            errorWidget: (_, _, _) => const AuroraBox(),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Offer detail (board §3.17, P9) — brand mark, discount, and Shop Now → the
/// affiliate link (external). Resolved from [offersProvider] by `?id=`.
class WtmOfferDetailScreen extends ConsumerWidget {
  const WtmOfferDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final offers = ref.watch(offersProvider).asData?.value ?? const <Offer>[];
    Offer? offer;
    for (final o in offers) {
      if (o.id == id) offer = o;
    }

    if (offer == null) {
      return WtmPage(
        title: l10n.wtmOffersTitle,
        eyebrow: l10n.wtmOfferEyebrow,
        children: [
          const SizedBox(height: WtmSpace.s22),
          WtmEmptyState(
            glyph: WtmGlyph.store,
            title: l10n.wtmOfferGoneTitle,
            message: l10n.wtmOfferGoneMessage,
            ctaLabel: l10n.wtmOffersTitle,
            onCta: () => context.go(AppRoute.wtmOffers),
          ),
        ],
      );
    }

    final o = offer;
    return WtmPage(
      title: o.brand ?? o.title,
      eyebrow: l10n.wtmOfferEyebrow,
      children: [
        SizedBox(
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(WtmRadius.card),
            child: o.imageUrl == null
                ? const AuroraBox(vignette: true)
                : CachedNetworkImage(
                    imageUrl: o.imageUrl!,
                    cacheKey: stableImageCacheKey(o.imageUrl!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (_, _) => const AuroraBox(vignette: true),
                    errorWidget: (_, _, _) => const AuroraBox(vignette: true),
                  ),
          ),
        ),
        const SizedBox(height: WtmSpace.s14),
        if ((o.discountLabel ?? '').isNotEmpty)
          Text(o.discountLabel!,
              textAlign: TextAlign.center,
              style: WtmType.goldItalic(WtmType.h1.copyWith(fontSize: 26))),
        const SizedBox(height: WtmSpace.s6),
        Text(o.title, textAlign: TextAlign.center, style: WtmType.sub),
        const SizedBox(height: WtmSpace.s16),
        GradientCta(
          label: l10n.wtmOfferShopNow,
          icon: const WtmIcon(WtmGlyph.store, size: 15, color: WtmColors.ctaText),
          onPressed: () => launchUrl(Uri.parse(o.affiliateUrl),
              mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: WtmSpace.s8),
        Text(l10n.wtmOfferExternalNote,
            textAlign: TextAlign.center, style: WtmType.micro),
      ],
    );
  }
}
