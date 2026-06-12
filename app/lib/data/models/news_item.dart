import 'package:freezed_annotation/freezed_annotation.dart';

part 'news_item.freezed.dart';
part 'news_item.g.dart';

/// A fashion-news item in the industry feed (CLAUDE.md §1 pillar 5). JSON keys
/// match the `/v1/news` response.
@freezed
abstract class NewsItem with _$NewsItem {
  const factory NewsItem({
    required String id,
    required String title,
    String? summary,
    String? source,
    String? url,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _NewsItem;

  factory NewsItem.fromJson(Map<String, dynamic> json) =>
      _$NewsItemFromJson(json);
}
