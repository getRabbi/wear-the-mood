import 'package:freezed_annotation/freezed_annotation.dart';

import 'poll.dart';

part 'post.freezed.dart';
part 'post.g.dart';

/// An OOTD post in the community feed (CLAUDE.md §1 pillar 4). JSON keys match
/// the `/v1/social` response (a post + its author + the viewer's like state).
@freezed
abstract class Post with _$Post {
  const factory Post({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'author_name') String? authorName,
    // The author's chosen public profile picture (signed display URL, resolved
    // server-side); null → the UI shows a monogram. Never the body/try-on photo.
    @JsonKey(name: 'author_avatar_url') String? authorAvatarUrl,
    String? caption,
    @JsonKey(name: 'image_url') String? imageUrl,
    // Smaller feed-list image (resolved server-side, where available); the full
    // [imageUrl] is shown on tap. Falls back to imageUrl when null.
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    @JsonKey(name: 'outfit_id') String? outfitId,
    @Default(<String>[]) List<String> tags,
    @JsonKey(name: 'like_count') @Default(0) int likeCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(name: 'liked_by_me') @Default(false) bool likedByMe,
    @JsonKey(name: 'is_edited') @Default(false) bool isEdited,
    @JsonKey(name: 'edited_at') DateTime? editedAt,
    Poll? poll,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _Post;

  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);
}
