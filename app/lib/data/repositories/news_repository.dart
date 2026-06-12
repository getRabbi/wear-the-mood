import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../models/news_item.dart';

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
}

final newsRepositoryProvider = Provider<NewsRepository>((ref) {
  return NewsRepository(ref.watch(dioProvider));
});
