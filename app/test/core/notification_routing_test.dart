import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/notifications/notification_routing.dart';
import 'package:app/core/push/push_messaging.dart';
import 'package:app/data/models/app_notification.dart';
import 'package:app/ui/widgets/wtm_icons.dart';

/// Type interpretation is centralised precisely so it can be pinned down here
/// instead of being re-derived by three widgets. These assertions mirror
/// `route_for` in `backend/app/services/notifications.py`; if the two drift, a
/// tapped push and a tapped inbox row stop agreeing on where they lead.
AppNotification _n({
  required String type,
  String? targetType,
  String? targetId,
  Map<String, dynamic> data = const {},
  bool isRead = false,
}) {
  return AppNotification(
    id: 'n1',
    type: type,
    title: 'title',
    targetType: targetType,
    targetId: targetId,
    data: data,
    isRead: isRead,
    createdAt: DateTime.utc(2026, 7, 31),
  );
}

void main() {
  group('destination', () {
    test('giveaway events open the listing', () {
      for (final type in [
        'giveaway',
        'giveaway_request',
        'giveaway_accepted',
        'giveaway_declined',
      ]) {
        expect(
          _n(type: type, targetType: 'giveaway', targetId: 'g1').route,
          '/wtm/giveaways/detail?id=g1',
          reason: type,
        );
      }
    });

    test('a chat message opens the CONVERSATION, not the listing', () {
      expect(
        _n(
          type: 'giveaway_message',
          targetType: 'giveaway_chat',
          targetId: 'g1',
        ).route,
        '/wtm/giveaway-chat?id=g1',
      );
    });

    test('a chat message falls back to the id carried in data', () {
      expect(
        _n(type: 'giveaway_message', data: const {'giveaway_id': 'g7'}).route,
        '/wtm/giveaway-chat?id=g7',
      );
    });

    test('post activity opens the post', () {
      expect(
        _n(type: 'like', targetType: 'post', targetId: 'p1').route,
        '/wtm/social/post?id=p1',
      );
      expect(
        _n(type: 'comment', targetType: 'post', targetId: 'p1').route,
        '/wtm/social/post?id=p1',
      );
    });

    test('a follow opens the follower profile', () {
      expect(
        _n(type: 'follow', targetType: 'user', targetId: 'u2').route,
        '/wtm/user?u=u2',
      );
    });

    test('an offer opens the offer', () {
      expect(
        _n(type: 'offer', targetType: 'offer', targetId: 'o1').route,
        '/wtm/offers/detail?id=o1',
      );
    });

    test('a referral reward opens the referral screen', () {
      expect(_n(type: 'referral_reward').route, '/wtm/referral');
    });

    test('an unknown type resolves to no destination rather than throwing', () {
      // A build older than the backend must still render and still be tappable.
      expect(_n(type: 'some_future_event').route, isNull);
      expect(
        _n(
          type: 'some_future_event',
          targetType: 'mystery',
          targetId: 'x',
        ).route,
        isNull,
      );
    });

    test('every produced route is a safe in-app path', () {
      final routes = [
        _n(type: 'giveaway', targetType: 'giveaway', targetId: 'g1').route,
        _n(
          type: 'giveaway_message',
          targetType: 'giveaway_chat',
          targetId: 'g',
        ).route,
        _n(type: 'like', targetType: 'post', targetId: 'p').route,
        _n(type: 'follow', targetType: 'user', targetId: 'u').route,
        _n(type: 'referral_reward').route,
      ];
      for (final route in routes) {
        expect(route, isNotNull);
        expect(isValidPushRoute(route!), isTrue, reason: route);
      }
    });
  });

  group('section', () {
    test('social events land in Activity', () {
      for (final type in ['like', 'comment', 'follow', 'mention', 'reply']) {
        expect(
          _n(type: type).section,
          NotificationSection.activity,
          reason: type,
        );
      }
    });

    test('giveaway and offer events land in Drops', () {
      for (final type in [
        'giveaway',
        'giveaway_request',
        'giveaway_accepted',
        'giveaway_declined',
        'giveaway_message',
        'offer',
      ]) {
        expect(_n(type: type).section, NotificationSection.drops, reason: type);
      }
    });

    test('anything else lands in System', () {
      expect(_n(type: 'credit_update').section, NotificationSection.system);
      expect(_n(type: 'some_future_event').section, NotificationSection.system);
    });

    test('the TYPE wins over a coincidental target', () {
      // A social event whose target happens to be a user must stay in Activity.
      expect(
        _n(type: 'follow', targetType: 'user', targetId: 'u1').section,
        NotificationSection.activity,
      );
    });
  });

  group('icon', () {
    test('each family gets its own glyph', () {
      expect(_n(type: 'like').glyph, WtmGlyph.heart);
      expect(_n(type: 'follow').glyph, WtmGlyph.users);
      expect(_n(type: 'comment').glyph, WtmGlyph.comment);
      expect(_n(type: 'giveaway_message').glyph, WtmGlyph.comment);
      expect(_n(type: 'giveaway_accepted').glyph, WtmGlyph.gift);
      expect(_n(type: 'offer').glyph, WtmGlyph.store);
      expect(_n(type: 'referral_reward').glyph, WtmGlyph.coin);
    });

    test('an unknown type still renders something', () {
      expect(_n(type: 'some_future_event').glyph, WtmGlyph.bell);
    });
  });
}
