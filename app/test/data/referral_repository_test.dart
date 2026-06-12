import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/referral_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test('getReferral parses code + stats', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'code': 'ABCD2345',
        'referral_count': 3,
        'reward_credits': 5,
      }),
    );

    final r = await ReferralRepository(dio).getReferral();

    expect(r.code, 'ABCD2345');
    expect(r.referralCount, 3);
    expect(r.rewardCredits, 5);
    expect(adapter.lastRequest!.path, '/v1/referrals');
  });

  test('redeem posts the code and returns the reward', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({'reward_credits': 5}),
    );

    final credits = await ReferralRepository(dio).redeem('friend123');

    expect(credits, 5);
    expect(adapter.lastRequest!.path, '/v1/referrals/redeem');
    expect(_body(adapter.lastRequest!.data)['code'], 'friend123');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'VALIDATION_ERROR', 'message': 'nope'},
      }, status: 422),
    );

    expect(
      () => ReferralRepository(dio).redeem('bad'),
      throwsA(isA<ApiException>()),
    );
  });
}
