import 'dart:typed_data';

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
import 'two_d/two_d_models.dart';

/// One history entry — either a server AI result (by URL) or a local 2D preview
/// (by bytes). Carries its mode so the grid can badge it "2D" vs "AI".
class _HistoryItem {
  _HistoryItem.ai(String imageUrl, this.date)
    : bytes = null,
      url = imageUrl,
      isTwoD = false;
  _HistoryItem.twoD(TwoDResult r)
    : bytes = r.bytes,
      url = null,
      date = r.createdAt,
      isTwoD = true;

  final Uint8List? bytes;
  final String? url;
  final DateTime? date;
  final bool isTwoD;
}

/// Saved try-on results (CLAUDE.md §8) — backend AI renders merged with local 2D
/// previews, newest first. Tap any result to view it full-screen.
class TryOnHistoryScreen extends ConsumerWidget {
  const TryOnHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ai = ref.watch(tryOnResultsProvider);
    final twoD = ref
        .watch(twoDResultsProvider)
        .map(_HistoryItem.twoD)
        .toList();

    List<_HistoryItem> merged(List<TryonResult> aiList) {
      final items = <_HistoryItem>[
        ...twoD,
        for (final r in aiList)
          if (r.resultImageUrl != null)
            _HistoryItem.ai(r.resultImageUrl!, r.createdAt),
      ]..sort((a, b) =>
          (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
      return items;
    }

    Widget grid(List<_HistoryItem> items) => RefreshIndicator(
      onRefresh: () async => ref.invalidate(tryOnResultsProvider),
      child: GridView.builder(
        padding: const EdgeInsets.all(AppSpace.lg),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSpace.md,
          crossAxisSpacing: AppSpace.md,
          childAspectRatio: 0.66,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => _ResultTile(item: items[i]),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tryonHistoryTitle)),
      body: SafeArea(
        child: ai.when(
          loading: () => twoD.isEmpty ? const _ShimmerGrid() : grid(twoD),
          error: (_, _) => twoD.isEmpty
              ? ErrorState(
                  title: l10n.tryonHistoryError,
                  onRetry: () => ref.invalidate(tryOnResultsProvider),
                  retryLabel: l10n.commonRetry,
                )
              : grid(twoD),
          data: (list) {
            final items = merged(list);
            return items.isEmpty
                ? EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: l10n.tryonHistoryEmptyTitle,
                    message: l10n.tryonHistoryEmptyMessage,
                    actionLabel: l10n.tryonHistoryStart,
                    onAction: () => context.go(AppRoute.tryon),
                  )
                : grid(items);
          },
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.item});

  final _HistoryItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final canOpen = item.bytes != null || item.url != null;

    return GestureDetector(
      onTap: canOpen ? () => _open(context, item) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.bytes != null)
                    Image.memory(item.bytes!, fit: BoxFit.cover)
                  else if (item.url != null)
                    CachedNetworkImage(
                      imageUrl: item.url!,
                      fit: BoxFit.cover,
                      fadeInDuration: AppMotion.base,
                      placeholder: (_, _) => const LoadingShimmer(
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                      ),
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: AppColors.mist),
                    )
                  else
                    const ColoredBox(color: AppColors.mist),
                  Positioned(
                    top: AppSpace.sm,
                    left: AppSpace.sm,
                    child: _ModeBadge(isTwoD: item.isTwoD),
                  ),
                ],
              ),
            ),
          ),
          if (item.date != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              DateFormat.yMMMd().add_jm().format(item.date!.toLocal()),
              style: text.bodySmall?.copyWith(color: AppColors.graphite),
            ),
          ] else
            const SizedBox(height: AppSpace.xs),
          Text(
            item.isTwoD ? l10n.tryOnBadgeFree : l10n.tryOnBadgePremium,
            style: text.bodySmall?.copyWith(
              color: item.isTwoD ? AppColors.success : AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.isTwoD});

  final bool isTwoD;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.scrim,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        isTwoD ? '2D' : 'AI',
        style: TextStyle(
          color: isTwoD ? AppColors.success : AppColors.lavender,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

void _open(BuildContext context, _HistoryItem item) {
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
                  child: item.bytes != null
                      ? Image.memory(item.bytes!, fit: BoxFit.contain)
                      : CachedNetworkImage(
                          imageUrl: item.url!,
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
