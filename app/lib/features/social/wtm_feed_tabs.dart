import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_providers.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';

/// The four WTM Community feed tabs (board 07). Each renders the SAME loaded
/// [feedProvider] page through a distinct, client-side transform, so switching
/// tabs never shows another tab's data (mobile QA #4). No new backend endpoint:
///
/// - [forYou]    → recommended: most-liked first, newest as the tiebreak.
/// - [following] → only posts by creators the viewer follows.
/// - [newest]    → strictly newest-first.
/// - [nearYou]   → location styling isn't available yet → a graceful, honest
///                 empty state (not a stale copy of For You).
enum WtmFeedTab { forYou, following, newest, nearYou }

/// Orders/filters [posts] for [tab]. [followingIds] is the viewer's follow set
/// (only consulted for [WtmFeedTab.following]). Pure + non-mutating so it is
/// trivially unit-testable and never touches the source list.
List<Post> applyWtmFeedTab(
  WtmFeedTab tab,
  List<Post> posts, {
  Set<String> followingIds = const {},
}) {
  switch (tab) {
    case WtmFeedTab.forYou:
      // Recommended = most-liked first, but a STABLE sort: posts with equal
      // engagement keep the backend's (newest-first) order, so the default tab
      // never reshuffles brand-new 0-like posts against each other.
      final indexed = [for (var i = 0; i < posts.length; i++) (i, posts[i])];
      indexed.sort((a, b) {
        final byLikes = b.$2.likeCount.compareTo(a.$2.likeCount);
        return byLikes != 0 ? byLikes : a.$1.compareTo(b.$1);
      });
      return [for (final e in indexed) e.$2];
    case WtmFeedTab.following:
      return [
        for (final p in posts)
          if (followingIds.contains(p.userId)) p,
      ];
    case WtmFeedTab.newest:
      return [...posts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case WtmFeedTab.nearYou:
      // No location signal yet — the tab renders its own graceful empty state.
      return const [];
  }
}

/// The set of user ids the current viewer follows (server truth), for the
/// Following tab's filter. Empty when signed out. Auto-disposes; invalidate it on
/// a pull-to-refresh of the Following tab so a new follow is picked up.
final myFollowingIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final me = ref.watch(authUserIdProvider);
  if (me == null) return <String>{};
  final following = await ref.watch(socialRepositoryProvider).getFollowing(me);
  return {for (final card in following) card.userId};
});
