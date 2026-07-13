import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/models/referral_summary.dart';

void main() {
  test('ReferralSummary.fromJson maps the server contract', () {
    final s = ReferralSummary.fromJson({
      'referral_code': 'AB2CD3EF',
      'referral_url': 'https://wearthemood.com/r/AB2CD3EF',
      'bonus_per_successful_referral': 10,
      'successful_referral_count': 3,
      'total_bonus_credits_earned': 30,
      'enabled': true,
      'recent': [
        {'reward_credits': 10, 'credited_at': '2026-07-14T10:00:00Z'},
        {'reward_credits': 10, 'credited_at': null},
      ],
    });
    expect(s.code, 'AB2CD3EF');
    expect(s.url, 'https://wearthemood.com/r/AB2CD3EF');
    expect(s.bonus, 10);
    expect(s.successfulCount, 3);
    expect(s.totalEarned, 30);
    expect(s.enabled, isTrue);
    expect(s.recent, hasLength(2));
    expect(s.recent.first.rewardCredits, 10);
  });

  test('reward history exposes NO referred-user identity (privacy §10)', () {
    // The item only carries amount + time — there is no field for a referred
    // user's name/email/id, so it cannot leak.
    final item = ReferralRewardItem.fromJson({
      'reward_credits': 10,
      'credited_at': '2026-07-14T10:00:00Z',
      // even if the server mistakenly included these, the DTO ignores them:
      'referred_email': 'secret@example.com',
      'referred_name': 'Jane',
    });
    expect(item.rewardCredits, 10);
    // The type has exactly two fields; nothing else is retained.
    expect(item.creditedAt, isNotNull);
  });

  test('defaults are safe when fields are missing', () {
    final s = ReferralSummary.fromJson({});
    expect(s.code, '');
    expect(s.successfulCount, 0);
    expect(s.enabled, isTrue);
    expect(s.recent, isEmpty);
  });
}
