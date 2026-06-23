import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/credits_repository.dart';

import '../helpers/fake_dio.dart';

void main() {
  test('getCredits fetches /v1/credits and parses the state', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'balance': 4,
        'daily_free_used': 1,
        'daily_free_limit': 5,
        'daily_free_remaining': 4,
        'total_available': 8,
      }),
    );

    final credits = await CreditsRepository(dio).getCredits();
    expect(adapter.lastRequest!.path, '/v1/credits');
    expect(credits.balance, 4);
    expect(credits.dailyFreeRemaining, 4);
    expect(credits.canSpend, isTrue);
  });

  test('getCredits maps an auth failure to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {
          'code': 'UNAUTHENTICATED',
          'message': 'Missing bearer token.',
        },
      }, status: 401),
    );

    expect(
      () => CreditsRepository(dio).getCredits(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.unauthenticated,
        ),
      ),
    );
  });
}
