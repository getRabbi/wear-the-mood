import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/models/offer.dart';
import '../../data/repositories/offers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Standalone **Offers** section — a Community sub-tab (flag-gated `feature_daily_offers`,
/// §16) of browsable affiliate deals. Kept OUT of the social feed AND the editorial
/// Newsroom (trust). Affiliate deep links log `affiliate_link_clicked` (§18); the
/// section logs `offer_viewed` once when deals first render. All four states (§4.3).
class OffersView extends ConsumerStatefulWidget {
  const OffersView({super.key});

  @override
  ConsumerState<OffersView> createState() => _OffersViewState();
}

class _OffersViewState extends ConsumerState<OffersView> {
  bool _tracked = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ref.watch(offersProvider).when(
          loading: _shimmer,
          error: (_, _) => ErrorState(
            title: l10n.offersErrorTitle,
            onRetry: () => ref.invalidate(offersProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (offers) {
            if (offers.isEmpty) {
              return EmptyState(
                icon: Icons.local_offer_outlined,
                title: l10n.offersEmptyTitle,
                message: l10n.offersEmptyMessage,
              );
            }
            if (!_tracked) {
              _tracked = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                ref.read(analyticsProvider).track(AnalyticsEvents.offerViewed);
              });
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(offersProvider),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.screenH,
                  AppSpace.md,
                  AppSpace.screenH,
                  bottomNavClearance(context),
                ),
                children: [
                  SectionHeader(
                    title: l10n.offersStripTitle,
                    subtitle: l10n.offersStripSubtitle,
                  ),
                  const SizedBox(height: AppSpace.md),
                  for (final offer in offers) ...[
                    _OfferCard(offer: offer),
                    const SizedBox(height: AppSpace.md),
                  ],
                ],
              ),
            );
          },
        );
  }

  Widget _shimmer() => ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: LoadingShimmer(
                width: double.infinity,
                height: 210,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
        ],
      );
}

/// A full-width affiliate offer card. Tap opens the affiliate link + logs the
/// click (§18).
class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.offer});

  final Offer offer;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(analyticsProvider).track(AnalyticsEvents.affiliateLinkClicked);
    final ok = await ref.read(linkLauncherProvider).open(offer.affiliateUrl);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.newsOpenError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Pressable(
      onTap: () => _open(context, ref),
      semanticLabel: offer.title,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.glassBorder),
          boxShadow: AppShadow.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  (offer.imageUrl != null && offer.imageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: offer.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => const DecoratedBox(
                            decoration:
                                BoxDecoration(gradient: AppGradients.brand),
                          ),
                        )
                      : const DecoratedBox(
                          decoration: BoxDecoration(gradient: AppGradients.brand),
                        ),
                  if (offer.discountLabel != null &&
                      offer.discountLabel!.isNotEmpty)
                    Positioned(
                      top: AppSpace.sm,
                      left: AppSpace.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          offer.discountLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offer.brand != null && offer.brand!.isNotEmpty)
                    Text(
                      offer.brand!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.muted,
                        letterSpacing: 0.6,
                        fontSize: 10.5,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    offer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Text(
                        l10n.offersShopNow,
                        style: text.labelLarge?.copyWith(color: AppColors.accent),
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          size: 16, color: AppColors.accent),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
