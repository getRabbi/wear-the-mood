import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/news_item.dart';
import '../models/wardrobe_item.dart';

/// Talks to the news endpoint (CLAUDE.md §1 pillar 5). Read-only public content;
/// the app never holds keys (§11).
class NewsRepository {
  NewsRepository(this._dio);

  final Dio _dio;

  /// Newest-first fashion news. Pass [before] (the oldest seen rank time) to page.
  Future<List<NewsItem>> getNews({int limit = 20, DateTime? before}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/v1/news',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before.toUtc().toIso8601String(),
        },
      );
      return (res.data ?? const [])
          .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// ONE story by id.
  ///
  /// The article reader used to resolve its story out of whatever the feed had
  /// already loaded, so a push notification or a shared link opened after a cold
  /// start found an empty list and claimed the story was gone. This is the
  /// authoritative lookup; the feed cache is still preferred when it has the
  /// story, so opening an article from the list costs no extra request.
  Future<NewsItem> getById(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/v1/news/$id');
      return NewsItem.fromJson(res.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  /// Trend-to-closet (§24): the user's own wardrobe pieces that match a news
  /// item's trend. Empty until the closet has been embedded server-side.
  Future<List<WardrobeItem>> getClosetMatches(String newsId) async {
    try {
      final res = await _dio.get<List<dynamic>>('/v1/news/$newsId/closet');
      return (res.data ?? const [])
          .map((e) => WardrobeItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(ref.watch(dioProvider));
});
