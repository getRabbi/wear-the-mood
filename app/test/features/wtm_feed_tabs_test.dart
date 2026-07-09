import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/post.dart';
import 'package:app/features/social/wtm_feed_tabs.dart';

/// Mobile QA #4: the four Community tabs each render the SAME loaded feed through
/// a distinct, client-side transform, so no tab shows another tab's data.

Post _p(String id, String user, {int likes = 0, required DateTime at}) =>
    Post(id: id, userId: user, likeCount: likes, createdAt: at);

void main() {
  final t0 = DateTime(2026, 1, 1, 8);
  final t1 = DateTime(2026, 1, 1, 9);
  final t2 = DateTime(2026, 1, 1, 10);

  // Backend order = newest first.
  final posts = [
    _p('new', 'u2', likes: 1, at: t2),
    _p('mid', 'u3', likes: 9, at: t1),
    _p('old', 'u1', likes: 5, at: t0),
  ];

  group('applyWtmFeedTab', () {
    test('forYou ranks by likes (recommended)', () {
      final r = applyWtmFeedTab(WtmFeedTab.forYou, posts);
      expect(r.map((p) => p.id).toList(), ['mid', 'old', 'new']); // 9, 5, 1
    });

    test('forYou is a STABLE sort — equal likes keep the feed order', () {
      final tie = [
        _p('a', 'u1', likes: 3, at: t0),
        _p('b', 'u2', likes: 3, at: t2),
      ];
      expect(
        applyWtmFeedTab(WtmFeedTab.forYou, tie).map((p) => p.id).toList(),
        ['a', 'b'],
      );
    });

    test('newest sorts strictly by createdAt desc', () {
      final r = applyWtmFeedTab(WtmFeedTab.newest, posts);
      expect(r.map((p) => p.id).toList(), ['new', 'mid', 'old']);
    });

    test('following keeps only followed authors, in feed order', () {
      final r = applyWtmFeedTab(
        WtmFeedTab.following,
        posts,
        followingIds: {'u2', 'u3'},
      );
      expect(r.map((p) => p.id).toList(), ['new', 'mid']);
    });

    test('following with no follows is empty', () {
      expect(applyWtmFeedTab(WtmFeedTab.following, posts), isEmpty);
    });

    test('nearYou is always empty (graceful location fallback)', () {
      expect(applyWtmFeedTab(WtmFeedTab.nearYou, posts), isEmpty);
    });

    test('never mutates the input list', () {
      final input = [...posts];
      applyWtmFeedTab(WtmFeedTab.forYou, input);
      applyWtmFeedTab(WtmFeedTab.newest, input);
      expect(input.map((p) => p.id).toList(), ['new', 'mid', 'old']);
    });
  });
}
