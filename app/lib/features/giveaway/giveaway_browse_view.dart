import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/giveaway.dart';
import '../../data/repositories/giveaway_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// The Community "Giveaway" tab body (FEATURES_COMMUNITY_PLUS · Giveaway): a
/// browse grid of available free pieces, with entries to list an item and to
/// view your own listings + requests.
class GiveawayBrowseView extends ConsumerWidget {
  const GiveawayBrowseView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(giveawayBrowseProvider);
    return Column(
      children: [
        const _GiveawayPromo(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenH,
            AppSpace.sm,
            AppSpace.screenH,
            AppSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: l10n.giveawayList,
                  icon: Icons.volunteer_activism_outlined,
                  dense: true,
                  onPressed: () => context.push(AppRoute.giveawayCreate),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              TextButton(
                onPressed: () => context.push(AppRoute.giveawaysMine),
                child: Text(l10n.giveawayMine),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => ErrorState(
              title: l10n.giveawayError,
              onRetry: () => ref.invalidate(giveawayBrowseProvider),
            ),
            data: (items) => items.isEmpty
                ? RefreshIndicator(
                    onRefresh: () async => ref.invalidate(giveawayBrowseProvider),
                    child: ListView(
                      children: [
                        const SizedBox(height: AppSpace.xxl),
                        EmptyState(
                          icon: Icons.volunteer_activism_outlined,
                          title: l10n.giveawayEmptyTitle,
                          message: l10n.giveawayEmptyMessage,
                          actionLabel: l10n.giveawayList,
                          onAction: () => context.push(AppRoute.giveawayCreate),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async => ref.invalidate(giveawayBrowseProvider),
                    child: GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.screenH,
                        AppSpace.sm,
                        AppSpace.screenH,
                        bottomNavClearance(context),
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: AppSpace.md,
                        crossAxisSpacing: AppSpace.md,
                        childAspectRatio: 0.74,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => GiveawayCard(
                        giveaway: items[i],
                        onTap: () => context.push(
                          AppRoute.giveawayDetail,
                          extra: items[i].id,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Warm give-it-forward banner at the top of the Giveaway section (Issue 3).
/// Editorial: serif headline on a soft accent surface, no loud gradient.
class _GiveawayPromo extends StatelessWidget {
  const _GiveawayPromo();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.md,
        AppSpace.screenH,
        AppSpace.xs,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.favorite_rounded,
                color: AppColors.accent, size: 20),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Serif headline tone (Fraunces via headlineSmall), kept small.
                  Text(
                    l10n.giveawayPromoTitle,
                    style: text.headlineSmall?.copyWith(
                      fontSize: 17,
                      height: 1.25,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    l10n.giveawayPromoSubtitle,
                    style: text.bodySmall?.copyWith(color: AppColors.graphite),
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

/// A giveaway tile for the browse / my-listings grids.
class GiveawayCard extends StatelessWidget {
  const GiveawayCard({super.key, required this.giveaway, required this.onTap});

  final Giveaway giveaway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final image = giveaway.images.isNotEmpty ? giveaway.images.first : null;
    return Pressable(
      onTap: onTap,
      semanticLabel: giveaway.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image != null)
                    CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: AppColors.tileLight),
                    )
                  else
                    const ColoredBox(color: AppColors.tileLight),
                  if (giveaway.status != 'available')
                    Positioned(
                      top: AppSpace.xs,
                      left: AppSpace.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.scrim,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          giveaway.status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            giveaway.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontSize: 14),
          ),
          Text(
            l10n.giveawayRequestsCount(giveaway.claimCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
