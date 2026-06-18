import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/comment.dart';
import '../models/leaderboard.dart';
import '../models/poll.dart';
import '../models/post.dart';
import '../models/public_profile.dart';
import '../models/wardrobe_item.dart';

/// Talks to the social endpoints (CLAUDE.md §1 pillar 4). Read-public,
/// write-own; the backend scopes every write to the JWT user and moderates post
/// images before they go public (§19). The app never holds keys (§11).
class SocialRepository {
  SocialRepository(this._dio);

  final Dio _dio;

  /// Newest-first public feed. Pass [before] (the oldest seen createdAt) to page.
  Future<List<Post>> getFeed({int limit = 20, DateTime? before}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/social/feed',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => Post.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Creates a post from an image and/or one of the user's own outfits, with an
  /// optional attached [poll] ({question, options, closes_at?}).
  Future<Post> createPost({
    String? caption,
    String? imageUrl,
    String? outfitId,
    List<String> tags = const [],
    Map<String, dynamic>? poll,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/social/posts',
        data: {
          'caption': ?caption,
          'image_url': ?imageUrl,
          'outfit_id': ?outfitId,
          'tags': tags,
          'poll': ?poll,
        },
      );
      return Post.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Casts the caller's vote on a poll (one per user, changeable until it
  /// closes). Returns fresh aggregate results + the caller's own choice.
  Future<Poll> votePoll(String pollId, int optionIndex) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/polls/$pollId/vote',
        data: {'option_index': optionIndex},
      );
      return Poll.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Edits the caller's own post (§19 — the backend re-moderates image + text).
  /// Send the full editable state; the server stamps it edited.
  Future<Post> editPost(
    String postId, {
    String? caption,
    String? imageUrl,
    String? outfitId,
    List<String> tags = const [],
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/v1/social/posts/$postId',
        data: {
          'caption': ?caption,
          'image_url': ?imageUrl,
          'outfit_id': ?outfitId,
          'tags': tags,
        },
      );
      return Post.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deletePost(String postId) =>
      _send(() => _dio.delete<void>('/v1/social/posts/$postId'));

  Future<void> like(String postId) =>
      _send(() => _dio.post<void>('/v1/social/posts/$postId/like'));

  Future<void> unlike(String postId) =>
      _send(() => _dio.delete<void>('/v1/social/posts/$postId/like'));

  Future<void> follow(String userId) =>
      _send(() => _dio.post<void>('/v1/social/follow/$userId'));

  Future<void> unfollow(String userId) =>
      _send(() => _dio.delete<void>('/v1/social/follow/$userId'));

  /// Block a user — they're filtered out of the feed both ways (§19).
  Future<void> block(String userId) =>
      _send(() => _dio.post<void>('/v1/social/block/$userId'));

  Future<void> unblock(String userId) =>
      _send(() => _dio.delete<void>('/v1/social/block/$userId'));

  /// File a UGC report on a post, comment, or user (§19).
  Future<void> report({
    required String subjectType,
    required String subjectId,
    String? reason,
  }) => _send(
    () => _dio.post<void>(
      '/v1/social/reports',
      data: {
        'subject_type': subjectType,
        'subject_id': subjectId,
        'reason': ?reason,
      },
    ),
  );

  Future<List<Comment>> getComments(
    String postId, {
    int limit = 50,
    DateTime? before,
  }) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/social/posts/$postId/comments',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => Comment.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Comment> addComment(String postId, String body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/v1/social/posts/$postId/comments',
        data: {'body': body},
      );
      return Comment.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  // ── public creator profiles + follow graph (CLAUDE.md §1 pillar 4) ─────────

  /// Another user's PUBLIC profile (safe fields only). 404 when the user is
  /// missing, private, or blocked either way.
  Future<PublicProfile> getPublicProfile(String userId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/social/users/$userId',
      );
      return PublicProfile.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// A creator's own public posts (their profile "Looks" tab).
  Future<List<Post>> getUserPosts(String userId, {int limit = 30}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/social/users/$userId/posts',
        queryParameters: {'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => Post.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Users who follow [userId].
  Future<List<PublicUserCard>> getFollowers(String userId, {int limit = 50}) =>
      _userCards('/v1/social/users/$userId/followers', limit);

  /// Users [userId] follows.
  Future<List<PublicUserCard>> getFollowing(String userId, {int limit = 50}) =>
      _userCards('/v1/social/users/$userId/following', limit);

  /// A creator's PUBLIC closet — empty unless they've opted in (safe item
  /// fields only; reuses [WardrobeItem] since the JSON keys match).
  Future<List<WardrobeItem>> getUserCloset(String userId, {int limit = 60}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/social/users/$userId/closet',
        queryParameters: {'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<PublicUserCard>> _userCards(String path, int limit) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        path,
        queryParameters: {'limit': limit},
      );
      return (res.data ?? const [])
          .map((e) => PublicUserCard.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// The monthly Style-Score leaderboard (top entries + the caller's standing).
  Future<Leaderboard> getLeaderboard() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/social/leaderboard',
      );
      return Leaderboard.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Shared wrapper for the fire-and-forget (204) endpoints.
  Future<void> _send(Future<void> Function() call) async {
    try {
      await call();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  return SocialRepository(ref.watch(dioProvider));
});

/// The monthly leaderboard. Auto-disposes so it refreshes on reopen.
final leaderboardProvider = FutureProvider.autoDispose<Leaderboard>((ref) {
  return ref.watch(socialRepositoryProvider).getLeaderboard();
});
