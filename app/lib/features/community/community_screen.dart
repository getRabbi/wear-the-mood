import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
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
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: [
            Tab(text: l10n.communityTabFeed),
            Tab(text: l10n.communityTabNews),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (context, _) => _tab.index == 0
            ? FloatingActionButton.extended(
                onPressed: () => context.push(AppRoute.socialCompose),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(l10n.feedCompose),
              )
            : const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tab,
          children: const [FeedView(), NewsView()],
        ),
      ),
    );
  }
}
