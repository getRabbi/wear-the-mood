import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics_events.dart';
import '../../core/analytics/analytics_provider.dart';
import '../../data/models/comment.dart';
import '../../data/models/post.dart';
import '../../data/repositories/social_repository.dart';

/// The community feed. An [AsyncNotifier] (not a plain FutureProvider) so likes
/// can update optimistically and comment counts can bump in place without a
/// full refetch.
class FeedController extends AsyncNotifier<List<Post>> {
  @override
  Future<List<Post>> build() {
    return ref.read(socialRepositoryProvider).getFeed();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(socialRepositoryProvider).getFeed(),
    );
  }

  /// Optimistically toggle a like, then sync with the backend; revert on error.
  Future<void> toggleLike(Post post) async {
    final list = state.asData?.value;
    if (list == null) return;
    final liked = !post.likedByMe;
    state = AsyncData(
      _replace(list, post.id, liked: liked, delta: liked ? 1 : -1),
    );

    final repo = ref.read(socialRepositoryProvider);
    try {
      if (liked) {
        await repo.like(post.id);
        await ref.read(analyticsProvider).track(AnalyticsEvents.postLiked);
      } else {
        await repo.unlike(post.id);
      }
    } catch (_) {
      // Revert to the original like state for this post.
      final now = state.asData?.value ?? list;
      state = AsyncData(
        _replace(now, post.id, liked: post.likedByMe, delta: liked ? -1 : 1),
      );
    }
  }

  /// Reflect a newly added comment in the post's count.
  void bumpCommentCount(String postId) {
    final list = state.asData?.value;
    if (list == null) return;
    state = AsyncData([
      for (final p in list)
        if (p.id == postId) p.copyWith(commentCount: p.commentCount + 1) else p,
    ]);
  }

  /// Drop a post locally after the user deletes it (avoids a refetch flash).
  void removeLocally(String postId) {
    final list = state.asData?.value;
    if (list == null) return;
    state = AsyncData([
      for (final p in list)
        if (p.id != postId) p,
    ]);
  }

  List<Post> _replace(
    List<Post> list,
    String id, {
    required bool liked,
    required int delta,
  }) {
    return [
      for (final p in list)
        if (p.id == id)
          p.copyWith(
            likedByMe: liked,
            likeCount: (p.likeCount + delta).clamp(0, 1 << 31),
          )
        else
          p,
    ];
  }
}

final feedProvider = AsyncNotifierProvider<FeedController, List<Post>>(
  FeedController.new,
);

/// Comments for one post, newest first. Auto-disposes when the sheet closes.
final postCommentsProvider = FutureProvider.autoDispose
    .family<List<Comment>, String>((ref, postId) {
      return ref.read(socialRepositoryProvider).getComments(postId);
    });
