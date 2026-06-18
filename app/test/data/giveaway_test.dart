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
}
