import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/calendar_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test('plan posts event titles and parses per-event outfits', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'plans': [
          {
            'title': 'Work meeting',
            'starts_at': null,
            'suggestion': {
              'title': 'Smart casual',
              'rationale': 'Polished but easy.',
              'items': [
                {'id': 't1', 'title': 'Shirt', 'image_url': 't1.jpg'},
              ],
            },
          },
        ],
      }),
    );

    final plans = await CalendarRepository(dio).plan(['Work meeting']);

    expect(plans, hasLength(1));
    expect(plans.first.title, 'Work meeting');
    expect(plans.first.suggestion.title, 'Smart casual');
    expect(plans.first.suggestion.items, hasLength(1));
    expect(adapter.lastRequest!.path, '/v1/calendar/plan');
    final body = _body(adapter.lastRequest!.data);
    expect((body['events'] as List).first['title'], 'Work meeting');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'UNAUTHENTICATED', 'message': 'no'},
      }, status: 401),
    );
    expect(
      () => CalendarRepository(dio).plan(['x']),
      throwsA(isA<ApiException>()),
    );
  });
}
