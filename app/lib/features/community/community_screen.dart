import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../challenges/challenge_providers.dart';
import '../news/news_screen.dart';
import '../social/feed_screen.dart';

/// Community hub (CLAUDE.md §1 pillar 4 + 5): the social feed and the fashion
/// Newsroom side by side as tabs. The "Share a look" FAB shows on the Community
/// tab; the leaderboard (Phase B) will surface here too.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.communityTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events_outlined),
            tooltip: l10n.feedChallenges,
            onPressed: () => context.push(AppRoute.challenges),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: l10n.notificationsTitle,
            onPressed: () => context.push(AppRoute.notifications),
          ),
          // Compose lives in the header (a FAB would collide with the floating
          // bottom nav).
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: AppColors.accent),
              icon: const Icon(Icons.add_a_photo_outlined, color: Colors.white),
              tooltip: l10n.feedCompose,
              onPressed: () => context.push(AppRoute.socialCompose),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l10n.communityTabFeed),
            Tab(text: l10n.communityTabNews),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The leaderboard + challenges hooks — only over the Community tab.
            AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => _tab.index == 0
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LeaderboardBanner(
                          onTap: () => context.push(AppRoute.leaderboard),
                        ),
                        const _ChallengesStrip(),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: const [FeedView(), NewsView()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardBanner extends StatelessWidget {
  const _LeaderboardBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        AppSpace.sm,
        AppSpace.screenH,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.20),
                  AppColors.accent.withValues(alpha: 0.16),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 15)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    l10n.leaderboardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.lavender, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal strip of active Style Challenges over the Community tab. Silent
/// when there are none (or while loading) so the feed never jumps.
class _ChallengesStrip extends ConsumerWidget {
  const _ChallengesStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final challenges =
        ref.watch(challengesProvider).asData?.value ?? const [];
    if (challenges.isEmpty) return const SizedBox.shrink();

    final shown = challenges.take(6).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                child: Text(
                  l10n.communityChallengesTitle,
                  style: text.titleMedium,
                ),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoute.challenges),
                child: Text(
                  l10n.communityChallengesSeeAll,
                  style: text.labelLarge?.copyWith(color: AppColors.lavender),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
            itemBuilder: (context, i) {
              final c = shown[i];
              return _ChallengeCard(
                title: c.title,
                entryCount: c.entryCount,
                onTap: () =>
                    context.push('${AppRoute.challenges}/${c.slug}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.title,
    required this.entryCount,
    required this.onTap,
  });

  final String title;
  final int entryCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: 184,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accent.withValues(alpha: 0.20),
                AppColors.violet.withValues(alpha: 0.16),
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.lavender, size: 20),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                l10n.challengeEntriesCount(entryCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
