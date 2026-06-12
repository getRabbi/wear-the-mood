import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/wardrobe_analytics.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/widgets.dart';
import 'wardrobe_providers.dart';

/// Wardrobe analytics — cost-per-wear + ROI (CLAUDE.md §24, pillar 2 data moat).
/// All four states (§4.3); pull to refresh.
class WardrobeInsightsScreen extends ConsumerWidget {
  const WardrobeInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final analytics = ref.watch(wardrobeAnalyticsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.insightsTitle)),
      body: SafeArea(
        child: analytics.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorState(
            title: l10n.insightsErrorTitle,
            onRetry: () => ref.invalidate(wardrobeAnalyticsProvider),
          ),
          data: (a) => a.itemCount == 0
              ? EmptyState(
                  icon: Icons.insights_outlined,
                  title: l10n.insightsEmptyTitle,
                  message: l10n.insightsEmptyMessage,
                )
              : RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(wardrobeAnalyticsProvider),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      _SummaryGrid(analytics: a),
                      const SizedBox(height: AppSpace.xl),
                      if (a.mostWorn != null)
                        _HighlightCard(
                          label: l10n.insightsMostWorn,
                          stat: a.mostWorn!,
                          trailing: l10n.insightsWears(a.mostWorn!.wearCount),
                        ),
                      if (a.bestValue != null)
                        _HighlightCard(
                          label: l10n.insightsBestValue,
                          stat: a.bestValue!,
                          trailing: _perWear(l10n, a.bestValue!.costPerWear),
                        ),
                      if (a.biggestWaste != null)
                        _HighlightCard(
                          label: l10n.insightsBiggestWaste,
                          stat: a.biggestWaste!,
                          trailing: a.biggestWaste!.wearCount == 0
                              ? l10n.insightsNeverWorn
                              : _perWear(l10n, a.biggestWaste!.costPerWear),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _perWear(AppLocalizations l10n, double? cpw) =>
      cpw == null ? '—' : l10n.insightsPerWear('\$${cpw.toStringAsFixed(2)}');
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.analytics});

  final WardrobeAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final spend = analytics.totalSpend;
    final avg = analytics.avgCostPerWear;
    final tiles = <(String, String)>[
      (l10n.insightsItems, '${analytics.itemCount}'),
      (l10n.insightsSpend, spend == null ? '—' : '\$${spend.toStringAsFixed(0)}'),
      (l10n.insightsTotalWears, '${analytics.totalWears}'),
      (l10n.insightsAvgPerWear, avg == null ? '—' : '\$${avg.toStringAsFixed(2)}'),
      (l10n.insightsNeverWornCount, '${analytics.neverWornCount}'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpace.md,
      crossAxisSpacing: AppSpace.md,
      childAspectRatio: 1.7,
      children: [for (final (label, value) in tiles) _StatTile(label: label, value: value)],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: text.headlineSmall),
          const SizedBox(height: AppSpace.xs),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.label,
    required this.stat,
    required this.trailing,
  });

  final String label;
  final WardrobeItemStat stat;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                width: 56,
                height: 72,
                child: (stat.imageUrl != null && stat.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: stat.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            const ColoredBox(color: AppColors.mist),
                      )
                    : const ColoredBox(color: AppColors.mist),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: text.bodySmall?.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    stat.title ?? '—',
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Text(trailing, style: text.titleMedium),
          ],
        ),
      ),
    );
  }
}
