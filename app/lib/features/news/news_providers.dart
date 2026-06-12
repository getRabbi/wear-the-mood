import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/news_item.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/news_repository.dart';

/// The fashion-news feed. Pull-to-refresh re-fetches via ref.invalidate.
final newsProvider = FutureProvider<List<NewsItem>>((ref) {
  return ref.read(newsRepositoryProvider).getNews();
});

/// Trend-to-closet matches for one news item (§24). Auto-disposes with the
/// sheet so re-opening refetches.
final closetMatchesProvider = FutureProvider.autoDispose
    .family<List<WardrobeItem>, String>((ref, newsId) {
      return ref.read(newsRepositoryProvider).getClosetMatches(newsId);
    });
