import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/news_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _news(String id) => {
  'id': id,
  'title': 'Quiet luxury endures',
  'summary': 'Muted palettes again.',
  'source': 'Fashion OS Wire',
  'url': 'https://example.com/$id',
  'image_url': null,
  'published_at': '2026-06-10T08:00:00Z',
  'created_at': '2026-06-10T09:00:00Z',
};

void main() {
  test('getNews parses items and sends the limit', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([_news('n1'), _news('n2')]),
    );

    final items = await NewsRepository(dio).getNews(limit: 15);

    expect(items, hasLength(2));
    expect(items.first.id, 'n1');
    expect(items.first.source, 'Fashion OS Wire');
    expect(items.first.url, 'https://example.com/n1');
    expect(adapter.lastRequest!.path, '/v1/news');
    expect(adapter.lastRequest!.queryParameters['limit'], 15);
  });

  test('getNews passes the before cursor', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(<Object>[]));
    await NewsRepository(
      dio,
    ).getNews(before: DateTime.utc(2026, 6, 1, 12));
    expect(adapter.lastRequest!.queryParameters['before'], contains('2026-06-01'));
  });

  test('getClosetMatches parses wardrobe items', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([
        {'id': 'w1', 'title': 'Beige trench', 'image_url': 'w1.jpg'},
      ]),
    );

    final items = await NewsRepository(dio).getClosetMatches('n1');

    expect(items, hasLength(1));
    expect(items.first.id, 'w1');
    expect(items.first.title, 'Beige trench');
    expect(adapter.lastRequest!.path, '/v1/news/n1/closet');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
      }, status: 500),
    );

    expect(
      () => NewsRepository(dio).getNews(),
      throwsA(isA<ApiException>()),
    );
  });
}
