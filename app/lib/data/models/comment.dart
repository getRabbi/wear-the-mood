import 'package:freezed_annotation/freezed_annotation.dart';

part 'comment.freezed.dart';
part 'comment.g.dart';

/// A comment on a post (CLAUDE.md §1 pillar 4). JSON keys match the
/// `/v1/social/posts/{id}/comments` response.
@freezed
abstract class Comment with _$Comment {
  const factory Comment({
    required String id,
    @JsonKey(name: 'post_id') required String postId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'author_name') String? authorName,
    // The commenter's public profile picture (signed display URL); null → monogram.
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    required String body,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Comment;

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);
}
