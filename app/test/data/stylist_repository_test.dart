import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/stylist_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

void main() {
  test('suggest posts optional context and parses the suggestion', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'title': 'Smart casual',
        'rationale': 'Mild and dry today.',
        'items': [
          {'id': 'a', 'title': 'Tee', 'image_url': 'a.jpg'},
          {'id': 'b', 'title': 'Jeans', 'thumbnail_url': 'b.jpg'},
        ],
      }),
    );

    final suggestion = await StylistRepository(dio).suggest(
      latitude: 23.78,
      longitude: 90.41,
      occasion: 'work',
    );

    expect(suggestion.title, 'Smart casual');
    expect(suggestion.rationale, 'Mild and dry today.');
    expect(suggestion.items, hasLength(2));
    expect(suggestion.items.first.displayImageUrl, 'a.jpg');
    expect(suggestion.items[1].displayImageUrl, 'b.jpg');

    final req = adapter.lastRequest!;
    expect(req.path, '/v1/stylist/suggest');
    final body = _body(req.data);
    expect(body['latitude'], 23.78);
    expect(body['occasion'], 'work');
    // Null context is omitted from the payload (null-aware map entries).
    expect(body.containsKey('note'), isFalse);
  });

  test('suggest omits coordinates when not provided', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'title': 'Look',
        'rationale': '',
        'items': <Object>[],
      }),
    );

    final suggestion = await StylistRepository(dio).suggest();

    expect(suggestion.isEmpty, isTrue);
    final body = _body(adapter.lastRequest!.data);
    expect(body.containsKey('latitude'), isFalse);
    expect(body.containsKey('longitude'), isFalse);
  });

  test('suggest maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'RATE_LIMITED', 'message': 'Slow down.'},
      }, status: 429),
    );

    expect(
      () => StylistRepository(dio).suggest(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCode.rateLimited)
            .having((e) => e.statusCode, 'statusCode', 429),
      ),
    );
  });
}
