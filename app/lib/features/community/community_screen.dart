import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
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
            // The leaderboard hook — only over the Community tab.
            AnimatedBuilder(
              animation: _tab,
              builder: (context, _) => _tab.index == 0
                  ? _LeaderboardBanner(
                      onTap: () => context.push(AppRoute.leaderboard),
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
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.violet.withValues(alpha: 0.22),
                  AppColors.accent.withValues(alpha: 0.18),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 18)),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    l10n.leaderboardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(fontSize: 14),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.lavender, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
