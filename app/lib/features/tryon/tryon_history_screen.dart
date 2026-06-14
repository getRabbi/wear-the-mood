import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/tryon_result.dart';
import '../../data/repositories/tryon_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';

/// Saved try-on results (CLAUDE.md §8) — a grid the user can browse to compare
/// how each look came out. Tap any result to view it full-screen.
class TryOnHistoryScreen extends ConsumerWidget {
  const TryOnHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final results = ref.watch(tryOnResultsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tryonHistoryTitle)),
      body: SafeArea(
        child: results.when(
          loading: () => const _ShimmerGrid(),
          error: (_, _) => ErrorState(
            title: l10n.tryonHistoryError,
            onRetry: () => ref.invalidate(tryOnResultsProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  icon: Icons.auto_awesome_outlined,
                  title: l10n.tryonHistoryEmptyTitle,
                  message: l10n.tryonHistoryEmptyMessage,
                  actionLabel: l10n.tryonHistoryStart,
                  onAction: () => context.go(AppRoute.tryon),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(tryOnResultsProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpace.md,
                          crossAxisSpacing: AppSpace.md,
                          childAspectRatio: 0.66,
                        ),
                    itemCount: list.length,
                    itemBuilder: (context, i) =>
                        _ResultTile(result: list[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final TryonResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = result.resultImageUrl;
    final date = result.createdAt;
    return GestureDetector(
      onTap: url == null ? null : () => _openResult(context, url),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: url == null
                  ? const ColoredBox(color: AppColors.mist)
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      width: double.infinity,
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
          if (date != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              DateFormat.yMMMd().add_jm().format(date.toLocal()),
              style: text.bodySmall?.copyWith(color: AppColors.graphite),
            ),
          ],
        ],
      ),
    );
  }
}

void _openResult(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpace.sm,
            right: AppSpace.sm,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpace.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.md,
        crossAxisSpacing: AppSpace.md,
        childAspectRatio: 0.66,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => LoadingShimmer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    );
  }
}
