import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/auth/auth_providers.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/social/public_profile_providers.dart';
import 'package:app/features/social/social_providers.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _post(String id) => {
  'id': id,
  'user_id': 'u1',
  'author_name': 'Mim',
  'image_url': '$id.jpg',
  'like_count': 0,
  'comment_count': 0,
  'liked_by_me': false,
  'created_at': '2026-06-11T10:00:00Z',
};

/// A controllable stand-in for the signed-in user id, so a test can simulate
/// sign-out / account switch by flipping its value.
class _AuthId extends Notifier<String?> {
  @override
  String? build() => 'u1';
  void set(String? id) => state = id;
}

final _authIdProvider = NotifierProvider<_AuthId, String?>(_AuthId.new);

void main() {
  late List<Map<String, dynamic>> feedBody;

  ProviderContainer makeContainer() {
    final (dio, _) = fakeDio((_) => jsonResponse(feedBody));
    final container = ProviderContainer(
      overrides: [
        socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
        authUserIdProvider.overrideWith((ref) => ref.watch(_authIdProvider)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => feedBody = [_post('p1')]);

  test('feed refetches on account switch — no stale posts carry over', () async {
    final container = makeContainer();

    expect((await container.read(feedProvider.future)).map((p) => p.id), ['p1']);

    // Account B's feed differs; switching identity must refetch, not reuse p1.
    feedBody = [_post('p2')];
    container.read(_authIdProvider.notifier).set('u2');

    expect((await container.read(feedProvider.future)).map((p) => p.id), ['p2']);
  });

  test('feed is empty when signed out (no unauthenticated fetch)', () async {
    final container = makeContainer();
    container.read(_authIdProvider.notifier).set(null);

    expect(await container.read(feedProvider.future), isEmpty);
  });

  test('removeLocally drops a deleted post from feed state immediately', () async {
    final container = makeContainer();
    feedBody = [_post('p1'), _post('p2')];

    await container.read(feedProvider.future);
    container.read(feedProvider.notifier).removeLocally('p1');

    expect(container.read(feedProvider).value!.map((p) => p.id), ['p2']);
  });

  test('follow set resets on account switch', () async {
    final container = makeContainer();

    container.read(followStoreProvider.notifier).seedOnce('x', following: true);
    expect(container.read(followStoreProvider), contains('x'));

    container.read(_authIdProvider.notifier).set('u2');
    expect(container.read(followStoreProvider), isEmpty);
  });

  test(
    'server delete + feed invalidate removes the post for a fresh fetch '
    '(what Account B / a new install sees)',
    () async {
      // A stateful fake backend: DELETE drops the row server-side, so the next
      // GET /feed (the authoritative refetch) no longer returns it.
      final live = <String>['p1', 'p2'];
      final (dio, _) = fakeDio((options) {
        if (options.method == 'DELETE' &&
            options.path.contains('/social/posts/')) {
          live.remove(options.path.split('/').last);
          return ResponseBody.fromString('', 204);
        }
        return jsonResponse([for (final id in live) _post(id)]);
      });
      final container = ProviderContainer(
        overrides: [
          socialRepositoryProvider.overrideWithValue(SocialRepository(dio)),
          authUserIdProvider.overrideWith((ref) => ref.watch(_authIdProvider)),
        ],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(feedProvider.future)).map((p) => p.id).toSet(),
        {'p1', 'p2'},
      );

      // Account A deletes p1 on the server, then the feed reconciles (invalidate).
      await container.read(socialRepositoryProvider).deletePost('p1');
      container.invalidate(feedProvider);

      // A fresh fetch (new account / fresh install) no longer sees it.
      expect(
        (await container.read(feedProvider.future)).map((p) => p.id).toSet(),
        {'p2'},
      );
    },
  );
}
