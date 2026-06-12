import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'news_providers.dart';

/// Bottom sheet showing the user's own wardrobe pieces that match a news item's
/// trend (CLAUDE.md §24, trend-to-closet). Open with [showClosetMatchesSheet].
Future<void> showClosetMatchesSheet(BuildContext context, String newsId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ClosetMatchesSheet(newsId: newsId),
  );
}

class _ClosetMatchesSheet extends ConsumerWidget {
  const _ClosetMatchesSheet({required this.newsId});

  final String newsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final matches = ref.watch(closetMatchesProvider(newsId));

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text(l10n.trendClosetTitle, style: text.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(
            child: matches.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ErrorState(
                title: l10n.trendClosetErrorTitle,
                onRetry: () => ref.invalidate(closetMatchesProvider(newsId)),
              ),
              data: (items) => items.isEmpty
                  ? EmptyState(
                      icon: Icons.checkroom_outlined,
                      title: l10n.trendClosetEmptyTitle,
                      message: l10n.trendClosetEmptyMessage,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(AppSpace.md),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: AppSpace.md,
                            crossAxisSpacing: AppSpace.md,
                            childAspectRatio: 0.6,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        return OutfitTile(
                          imageUrl: item.displayImageUrl ?? '',
                          label: item.title,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the sheet and fires the trend-to-closet analytics event (§15).
void openClosetMatches(BuildContext context, WidgetRef ref, String newsId) {
  ref.read(analyticsProvider).track(AnalyticsEvents.trendClosetOpened);
  showClosetMatchesSheet(context, newsId);
}
