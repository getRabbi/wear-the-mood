import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/post.dart';
import '../../l10n/app_localizations.dart';

/// Community feed filter chips. `forYou`/`following` show the feed as-is,
/// `trending` sorts by likes, and the style filters keep posts whose tags match —
/// all client-side over the existing feed (no new endpoint).
enum CommunityFilter {
  forYou,
  following,
  trending,
  hijab,
  modest,
  minimal,
  casual,
  wedding,
  office,
}

extension CommunityFilterX on CommunityFilter {
  String label(AppLocalizations l10n) => switch (this) {
    CommunityFilter.forYou => l10n.communityCatForYou,
    CommunityFilter.following => l10n.communityCatFollowing,
    CommunityFilter.trending => l10n.communityCatTrending,
    CommunityFilter.hijab => l10n.communityCatHijab,
    CommunityFilter.modest => l10n.communityCatModest,
    CommunityFilter.minimal => l10n.communityCatMinimal,
    CommunityFilter.casual => l10n.communityCatCasual,
    CommunityFilter.wedding => l10n.communityCatWedding,
    CommunityFilter.office => l10n.communityCatOffice,
  };

  List<String> get _keywords => switch (this) {
    CommunityFilter.hijab => const ['hijab', 'modest', 'abaya', 'scarf'],
    CommunityFilter.modest => const ['modest', 'abaya', 'covered', 'hijab'],
    CommunityFilter.minimal => const ['minimal', 'clean', 'neutral', 'basic'],
    CommunityFilter.casual => const ['casual', 'everyday', 'weekend'],
    CommunityFilter.wedding => const ['wedding', 'bridal', 'guest', 'reception'],
    CommunityFilter.office => const ['office', 'work', 'formal', 'business'],
    _ => const [],
  };

  /// Apply this filter to the feed list (non-mutating).
  List<Post> apply(List<Post> posts) {
    switch (this) {
      case CommunityFilter.forYou:
      case CommunityFilter.following:
        return posts;
      case CommunityFilter.trending:
        final sorted = [...posts]
          ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
        return sorted;
      default:
        final keys = _keywords;
        return posts
            .where((p) => p.tags.any(
                  (t) => keys.any(t.toLowerCase().contains),
                ))
            .toList();
    }
  }
}

class CommunityFilterNotifier extends Notifier<CommunityFilter> {
  @override
  CommunityFilter build() => CommunityFilter.forYou;

  void select(CommunityFilter filter) => state = filter;
}

final communityFilterProvider =
    NotifierProvider<CommunityFilterNotifier, CommunityFilter>(
  CommunityFilterNotifier.new,
);
