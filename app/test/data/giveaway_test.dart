import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/giveaway.dart';

void main() {
  test('Giveaway.fromJson maps snake_case + helpers', () {
    final g = Giveaway.fromJson({
      'id': 'g1',
      'owner_id': 'u1',
      'owner_name': 'Ada',
      'wardrobe_item_id': 'w1',
      'title': 'Wool coat',
      'description': 'Barely worn',
      'images': ['https://x/1.jpg'],
      'size': 'M',
      'category': 'Outerwear',
      'condition': 'Like new',
      'area_label': 'Dhanmondi',
      'status': 'available',
      'is_mine': false,
      'my_claim_status': null,
      'claim_count': 2,
      'created_at': '2026-06-19T00:00:00Z',
    });
    expect(g.title, 'Wool coat');
    expect(g.images.single, 'https://x/1.jpg');
    expect(g.claimCount, 2);
    expect(g.isAvailable, isTrue);
    expect(g.hasClaimed, isFalse);
  });

  test('a claimed, reserved giveaway reflects the helpers', () {
    final g = Giveaway.fromJson({
      'id': 'g2',
      'owner_id': 'u1',
      'title': 'Dress',
      'images': <String>[],
      'status': 'reserved',
      'my_claim_status': 'accepted',
      'claim_count': 1,
      'created_at': '2026-06-19T00:00:00Z',
    });
    expect(g.isAvailable, isFalse);
    expect(g.hasClaimed, isTrue);
    expect(g.myClaimStatus, 'accepted');
  });

  test('GiveawayClaim.fromJson maps fields', () {
    final c = GiveawayClaim.fromJson({
      'id': 'c1',
      'giveaway_id': 'g1',
      'claimer_id': 'u2',
      'claimer_name': 'Lin',
      'message': 'Is this still available?',
      'status': 'requested',
      'created_at': '2026-06-19T00:00:00Z',
    });
    expect(c.claimerName, 'Lin');
    expect(c.status, 'requested');
  });

  test('GiveawayPickupChat.fromJson maps fields + activity/plan helpers', () {
    final chat = GiveawayPickupChat.fromJson({
      'id': 'pc1',
      'giveaway_id': 'g1',
      'giveaway_title': 'Wool coat',
      'owner_id': 'u1',
      'requester_id': 'u2',
      'other_name': 'Ada',
      'is_owner': false,
      'status': 'active',
      'report_flag': false,
      'pickup_plan': {
        'area': 'Dhanmondi',
        'landmark': 'Lake gate 2',
        'time_slot': 'Sat 5pm',
        'confirmed': true,
      },
      'approved_at': '2026-07-09T00:00:00Z',
      'expires_at':
          DateTime.now().toUtc().add(const Duration(days: 5)).toIso8601String(),
      'created_at': '2026-07-09T00:00:00Z',
    });
    expect(chat.isActive, isTrue);
    expect(chat.timeLeft.inDays, inInclusiveRange(4, 5));
    expect(chat.planArea, 'Dhanmondi');
    expect(chat.planLandmark, 'Lake gate 2');
    expect(chat.planTimeSlot, 'Sat 5pm');
    expect(chat.planConfirmed, isTrue);
    expect(chat.hasPlan, isTrue);
  });

  test('a past-expiry chat is inactive even if the status is stale', () {
    final chat = GiveawayPickupChat.fromJson({
      'id': 'pc2',
      'giveaway_id': 'g1',
      'owner_id': 'u1',
      'requester_id': 'u2',
      'status': 'active', // server hasn't flipped it yet
      'approved_at': '2026-06-01T00:00:00Z',
      'expires_at': '2026-06-08T00:00:00Z', // long past
      'created_at': '2026-06-01T00:00:00Z',
    });
    expect(chat.isActive, isFalse);
    expect(chat.timeLeft, Duration.zero);
    expect(chat.hasPlan, isFalse);
  });

  test('GiveawayChatMessage.fromJson maps a redacted body to null', () {
    final m = GiveawayChatMessage.fromJson({
      'id': 'm1',
      'chat_id': 'pc1',
      'sender_id': 'u2',
      'is_mine': false,
      'body': null,
      'body_deleted': true,
      'created_at': '2026-07-09T10:00:00Z',
    });
    expect(m.bodyDeleted, isTrue);
    expect(m.body, isNull);
  });
}
