import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/news_item.dart';
import '../../data/models/wardrobe_item.dart';
import '../../data/repositories/news_repository.dart';

/// The fashion-news feed. Pull-to-refresh re-fetches via ref.invalidate.
final newsProvider = FutureProvider<List<NewsItem>>((ref) {
  return ref.read(newsRepositoryProvider).getNews();
});

/// ONE story, for the article reader.
///
/// Feed-first, network-second: when [newsProvider] already holds the story —
/// which is every tap from the Newsroom list — this resolves synchronously and
/// costs nothing. Only a cold open (a push notification, a shared link, an
/// article the feed has since paged past) reaches the server, and it fetches
/// that ONE story rather than re-pulling the whole feed.
///
/// Throws [ApiException] with a 404 for a story that no longer exists, which the
/// reader renders as its unavailable state.
final newsItemProvider = FutureProvider.autoDispose.family<NewsItem, String>((
  ref,
  id,
) async {
  final cached = ref.read(newsProvider).asData?.value;
  if (cached != null) {
    for (final item in cached) {
      if (item.id == id) return item;
    }
  }
  return ref.read(newsRepositoryProvider).getById(id);
});

/// Trend-to-closet matches for one news item (§24). Auto-disposes with the
/// sheet so re-opening refetches.
final closetMatchesProvider = FutureProvider.autoDispose
    .family<List<WardrobeItem>, String>((ref, newsId) {
      return ref.read(newsRepositoryProvider).getClosetMatches(newsId);
    });
