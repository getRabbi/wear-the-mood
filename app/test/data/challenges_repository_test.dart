import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/challenges_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

Map<String, dynamic> _challenge(String id, {int entries = 0, bool joined = false}) => {
  'id': id,
  'slug': 'monochrome',
  'title': 'Monochrome',
  'prompt': 'Style an all-one-colour look.',
  'cover_url': '$id.jpg',
  'starts_at': '2026-06-01T00:00:00Z',
  'ends_at': null,
  'entry_count': entries,
  'joined_by_me': joined,
};

void main() {
  test('listChallenges parses challenges', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([_challenge('c1', entries: 3, joined: true)]),
    );

    final list = await ChallengesRepository(dio).listChallenges();

    expect(list, hasLength(1));
    expect(list.first.id, 'c1');
    expect(list.first.entryCount, 3);
    expect(list.first.joinedByMe, isTrue);
    expect(adapter.lastRequest!.path, '/v1/challenges');
  });

  test('getChallenge fetches by slug', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_challenge('c1')));

    final c = await ChallengesRepository(dio).getChallenge('monochrome');

    expect(c.slug, 'monochrome');
    expect(adapter.lastRequest!.path, '/v1/challenges/monochrome');
  });

  test('join posts the post id and parses the updated challenge', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(_challenge('c1', entries: 1, joined: true), status: 201),
    );

    final c = await ChallengesRepository(dio).join('c1', 'p9');

    expect(c.joinedByMe, isTrue);
    expect(adapter.lastRequest!.path, '/v1/challenges/c1/join');
    expect(adapter.lastRequest!.method, 'POST');
    expect(_body(adapter.lastRequest!.data)['post_id'], 'p9');
  });

  test('leave hits the entries path with DELETE', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );

    await ChallengesRepository(dio).leave('c1', 'p9');

    expect(adapter.lastRequest!.path, '/v1/challenges/c1/entries/p9');
    expect(adapter.lastRequest!.method, 'DELETE');
  });

  test('getEntries parses entries and sends the limit', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([
        {
          'id': 'e1',
          'challenge_id': 'c1',
          'post_id': 'p1',
          'user_id': 'u1',
          'author_name': 'Mim',
          'image_url': 'p1.jpg',
          'caption': 'ootd',
          'created_at': '2026-06-11T10:00:00Z',
        },
      ]),
    );

    final entries = await ChallengesRepository(dio).getEntries('c1', limit: 10);

    expect(entries, hasLength(1));
    expect(entries.first.authorName, 'Mim');
    expect(adapter.lastRequest!.path, '/v1/challenges/c1/entries');
    expect(adapter.lastRequest!.queryParameters['limit'], 10);
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'NOT_FOUND', 'message': 'gone'},
      }, status: 404),
    );

    expect(
      () => ChallengesRepository(dio).getChallenge('nope'),
      throwsA(isA<ApiException>()),
    );
  });
}
