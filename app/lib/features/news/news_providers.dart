import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/news_item.dart';
import '../../data/repositories/news_repository.dart';

/// The fashion-news feed. Pull-to-refresh re-fetches via ref.invalidate.
final newsProvider = FutureProvider<List<NewsItem>>((ref) {
  return ref.read(newsRepositoryProvider).getNews();
});
