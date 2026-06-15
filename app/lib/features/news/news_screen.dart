import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/link_launcher.dart';
import '../../data/models/news_item.dart';
import '../../data/repositories/shop_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/html.dart';
import '../../shared/widgets/widgets.dart';
import 'closet_matches_sheet.dart';
import 'news_providers.dart';

/// The fashion-news feed — industry buzz, trends and drops (CLAUDE.md §1
/// pillar 5). All four states (§4.3); pull to refresh; tapping opens the source.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.newsTitle)),
      body: const SafeArea(child: NewsView()),
    );
  }
}

/// The fashion-news feed body (no Scaffold) — reused by [NewsScreen] and the
/// Newsroom tab of `CommunityScreen`.
class NewsView extends ConsumerWidget {
  const NewsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final news = ref.watch(newsProvider);
    return news.when(
      loading: () => const _NewsShimmer(),
      error: (_, _) => ErrorState(
        title: l10n.newsErrorTitle,
        onRetry: () => ref.invalidate(newsProvider),
      ),
      data: (items) => items.isEmpty
          ? EmptyState(
              icon: Icons.article_outlined,
              title: l10n.newsEmptyTitle,
              message: l10n.newsEmptyMessage,
            )
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(newsProvider),
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(
                  AppSpace.screenH,
                  AppSpace.md,
                  AppSpace.screenH,
                  bottomNavClearance(context),
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _NewsCard(item: items[i]),
              ),
            ),
    );
  }
}

class _NewsCard extends ConsumerWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final url = item.url;
    if (url == null || url.isEmpty) return;
    final ok = await ref.read(linkLauncherProvider).open(url);
    if (!ok && context.mounted) _snack(context, l10n.newsOpenError);
  }

  /// Shop-the-look (§18, §24): open an affiliate search for this trend + log it.
  Future<void> _shop(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final url = await ref
          .read(shopRepositoryProvider)
          .shopLink(item.title, label: l10n.newsShopAction);
      await ref
          .read(analyticsProvider)
          .track(AnalyticsEvents.affiliateLinkClicked);
      final ok = await ref.read(linkLauncherProvider).open(url);
      if (!ok && context.mounted) _snack(context, l10n.newsOpenError);
    } on ApiException {
      if (context.mounted) _snack(context, l10n.newsOpenError);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    // Keep raw HTML (<p>, <img>, src, URLs) out of the UI: clean the summary and
    // fall back to an <img> embedded in the HTML when there's no image_url.
    final summary = stripHtml(item.summary);
    final imageUrl = (item.imageUrl != null && item.imageUrl!.isNotEmpty)
        ? item.imageUrl
        : extractImageUrl(item.summary);
    final date = item.publishedAt ?? item.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: GlassCard(
        padding: EdgeInsets.zero,
        onTap: () => _open(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.card),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: AppMotion.base,
                    placeholder: (_, _) => const LoadingShimmer(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                    ),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: AppColors.mist),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.source != null &&
                          item.source!.trim().isNotEmpty)
                        Expanded(
                          child: Text(
                            item.source!.trim().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      Text(
                        DateFormat('MMM d').format(date),
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(item.title, style: text.titleMedium),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      summary,
                      style: text.bodyMedium?.copyWith(color: AppColors.graphite),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpace.sm),
                  Wrap(
                    spacing: AppSpace.sm,
                    children: [
                      TextButton.icon(
                        onPressed: () =>
                            openClosetMatches(context, ref, item.id),
                        icon: const Icon(Icons.checkroom_outlined, size: 18),
                        label: Text(l10n.trendClosetAction),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _shop(context, ref),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                        label: Text(l10n.newsShopAction),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.sm,
                          ),
                        ),
                      ),
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

class _NewsShimmer extends StatelessWidget {
  const _NewsShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: 4,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: LoadingShimmer(
          width: double.infinity,
          height: 240,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }
}
