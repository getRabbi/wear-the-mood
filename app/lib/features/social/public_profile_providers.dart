import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/post.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/social_repository.dart';

/// Another user's public profile (safe fields only, CLAUDE.md §1 pillar 4).
/// Auto-disposes so it refreshes whenever a profile page is reopened.
final publicProfileProvider = FutureProvider.autoDispose
    .family<PublicProfile, String>((ref, userId) {
      return ref.watch(socialRepositoryProvider).getPublicProfile(userId);
    });

/// A creator's own public posts (their "Looks" grid).
final userPostsProvider = FutureProvider.autoDispose
    .family<List<Post>, String>((ref, userId) {
      return ref.watch(socialRepositoryProvider).getUserPosts(userId);
    });

/// Users who follow [userId].
final followersProvider = FutureProvider.autoDispose
    .family<List<PublicUserCard>, String>((ref, userId) {
      return ref.watch(socialRepositoryProvider).getFollowers(userId);
    });

/// Users [userId] follows.
final followingProvider = FutureProvider.autoDispose
    .family<List<PublicUserCard>, String>((ref, userId) {
      return ref.watch(socialRepositoryProvider).getFollowing(userId);
    });

/// In-memory follow graph for the *current* user: the set of user ids they
/// follow. The community feed buttons and every profile page read this so a
/// follow tapped in one place is reflected everywhere instantly (optimistic),
/// without each card carrying its own server flag.
///
/// Server truth is folded in via [seedOnce] when a profile/card loads; a user's
/// own tap (via [toggle]) always wins over a later refetch of the same id.
class FollowStore extends Notifier<Set<String>> {
  final Set<String> _decided = <String>{};

  @override
  Set<String> build() => <String>{};

  bool isFollowing(String id) => state.contains(id);

  /// Seed server truth once per id (ignored after the first decision for that id
  /// so an optimistic tap is never clobbered by a stale refetch).
  void seedOnce(String id, {required bool following}) {
    if (_decided.contains(id)) return;
    _decided.add(id);
    if (following && !state.contains(id)) state = {...state, id};
  }

  void _set(String id, {required bool following}) {
    _decided.add(id);
    if (following == state.contains(id)) return;
    state = following ? {...state, id} : ({...state}..remove(id));
  }

  /// Optimistically toggle, call the API, revert on failure. Returns the new
  /// following state.
  Future<bool> toggle(String id, SocialRepository repo) async {
    final next = !state.contains(id);
    _set(id, following: next);
    try {
      if (next) {
        await repo.follow(id);
      } else {
        await repo.unfollow(id);
      }
    } catch (_) {
      _set(id, following: !next); // revert
      rethrow;
    }
    return next;
  }
}

final followStoreProvider = NotifierProvider<FollowStore, Set<String>>(
  FollowStore.new,
);
