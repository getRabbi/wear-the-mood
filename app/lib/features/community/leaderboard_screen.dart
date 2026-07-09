import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/leaderboard.dart';
import '../../data/repositories/social_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/utils/public_name.dart';
import '../../shared/widgets/widgets.dart';

/// The monthly Style-Score leaderboard (CLAUDE.md §1 pillar 4, §24) — a game-like
/// ranking where #1 wins a free month of Premium. Shows the prize, a countdown,
/// your standing, the ranked list, and past winners.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final board = ref.watch(leaderboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.leaderboardTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: l10n.leaderboardHowTooltip,
            onPressed: () => _showHowPointsSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: board.when(
          loading: () => PremiumLogoLoader(label: l10n.loadingCommunity),
          error: (_, _) => ErrorState(
            title: l10n.leaderboardError,
            onRetry: () => ref.invalidate(leaderboardProvider),
            retryLabel: l10n.commonRetry,
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(leaderboardProvider),
            child: ListView(
              padding: const EdgeInsets.all(AppSpace.lg),
              children: [
                _PrizeBanner(daysLeft: _daysLeft(data.month)),
                const SizedBox(height: AppSpace.lg),
                _YourRank(rank: data.myRank, score: data.myScore),
                const SizedBox(height: AppSpace.lg),
                if (data.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                    child: Text(
                      l10n.leaderboardEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  for (final e in data.entries) _RankRow(entry: e),
                if (data.recentWinners.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xl),
                  _PastWinners(winners: data.recentWinners),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Days until the month resets (when the winner is decided), from "YYYY-MM".
  int _daysLeft(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return 0;
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final reset = DateTime(year, m + 1, 1);
    final left = reset.difference(DateTime.now()).inDays;
    return left < 0 ? 0 : left;
  }
}

/// "How points work" explainer — documents the REAL scoring from the backend
/// `_RANKED_CTE` (social.py): +5 per post, +1 per like received, +3 per comment
/// received, this calendar month, self-engagement excluded. Keep these in sync if
/// that SQL changes.
void _showHowPointsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _HowPointsSheet(),
  );
}

class _HowPointsSheet extends StatelessWidget {
  const _HowPointsSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppColors.mist,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Text(l10n.leaderboardHowTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpace.xs),
            Text(l10n.leaderboardHowIntro, style: text.bodyMedium),
            const SizedBox(height: AppSpace.lg),
            // Values mirror social.py `_RANKED_CTE` (5 / 1 / 3).
            _PointRow(
              icon: Icons.add_a_photo_outlined,
              label: l10n.leaderboardHowPost,
              points: l10n.leaderboardHowPoints(5),
            ),
            _PointRow(
              icon: Icons.favorite_border_rounded,
              label: l10n.leaderboardHowLike,
              points: l10n.leaderboardHowPoints(1),
            ),
            _PointRow(
              icon: Icons.mode_comment_outlined,
              label: l10n.leaderboardHowComment,
              points: l10n.leaderboardHowPoints(3),
            ),
            const SizedBox(height: AppSpace.md),
            _Note(text: l10n.leaderboardHowNoSelf),
            _Note(text: l10n.leaderboardHowMonthly),
            const SizedBox(height: AppSpace.lg),
            SecondaryButton(
              label: l10n.commonClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One scoring row: action on the left, a points pill on the right.
class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.icon,
    required this.label,
    required this.points,
  });

  final IconData icon;
  final String label;
  final String points;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(label, style: text.bodyMedium)),
          const SizedBox(width: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              points,
              style: text.labelLarge?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A muted scoring caveat (anti-gaming / monthly reset).
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: AppColors.graphite),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              style: style.bodySmall?.copyWith(color: AppColors.graphite),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrizeBanner extends StatelessWidget {
  const _PrizeBanner({required this.daysLeft});

  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.accentGlow,
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 40)),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.leaderboardPrize,
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  l10n.leaderboardDaysLeft(daysLeft),
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _YourRank extends StatelessWidget {
  const _YourRank({required this.rank, required this.score});

  final int? rank;
  final int score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.bar_chart_rounded, color: AppColors.accent, size: 28),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Text(
              rank == null
                  ? l10n.leaderboardYouUnranked
                  : l10n.leaderboardYourRank,
              style: text.titleMedium,
            ),
          ),
          if (rank != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('#$rank', style: text.titleMedium),
                Text(l10n.leaderboardScore(score), style: text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final medal = switch (entry.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: entry.isMe ? AppColors.accentSoft : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          // Tap a rower to open their public profile (id is always present).
          onTap: () => context.push(
            AppRoute.userProfilePath(entry.userId),
            extra: publicName(entry.displayName),
          ),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: medal != null
                      ? Text(medal, style: const TextStyle(fontSize: 22))
                      : Text(
                          '${entry.rank}',
                          style: text.titleMedium?.copyWith(
                            color: AppColors.graphite,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    entry.isMe
                        ? l10n.leaderboardYouLabel
                        : (publicName(entry.displayName) ?? l10n.socialSomeone),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      fontWeight: entry.isMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Text(l10n.leaderboardScore(entry.score), style: text.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PastWinners extends StatelessWidget {
  const _PastWinners({required this.winners});

  final List<PastWinner> winners;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.leaderboardPastWinners, style: text.titleMedium),
        const SizedBox(height: AppSpace.sm),
        for (final w in winners)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 16)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    publicName(w.displayName) ?? l10n.socialSomeone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Text(
                  w.month,
                  style: text.bodySmall?.copyWith(color: AppColors.graphite),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
