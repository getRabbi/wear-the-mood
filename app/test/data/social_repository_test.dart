import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/core/network/api_exception.dart';
import 'package:app/data/repositories/social_repository.dart';

import '../helpers/fake_dio.dart';

Map<String, dynamic> _body(dynamic data) =>
    (data is String ? jsonDecode(data) : data) as Map<String, dynamic>;

Map<String, dynamic> _post(String id) => {
  'id': id,
  'user_id': 'u1',
  'author_name': 'Mim',
  'caption': 'ootd',
  'image_url': '$id.jpg',
  'like_count': 2,
  'comment_count': 1,
  'liked_by_me': false,
  'created_at': '2026-06-11T10:00:00Z',
};

void main() {
  test('getFeed parses posts and sends the limit', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse([_post('p1'), _post('p2')]),
    );

    final posts = await SocialRepository(dio).getFeed(limit: 10);

    expect(posts, hasLength(2));
    expect(posts.first.id, 'p1');
    expect(posts.first.authorName, 'Mim');
    expect(posts.first.likeCount, 2);
    expect(adapter.lastRequest!.path, '/v1/social/feed');
    expect(adapter.lastRequest!.queryParameters['limit'], 10);
  });

  test('createPost posts caption/image/outfit and parses the result', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_post('p9')));

    final post = await SocialRepository(
      dio,
    ).createPost(caption: 'hi', imageUrl: 'cover.jpg', outfitId: 'o1');

    expect(post.id, 'p9');
    final body = _body(adapter.lastRequest!.data);
    expect(body['caption'], 'hi');
    expect(body['image_url'], 'cover.jpg');
    expect(body['outfit_id'], 'o1');
  });

  test('createPost omits null fields', () async {
    final (dio, adapter) = fakeDio((_) => jsonResponse(_post('p1')));
    await SocialRepository(dio).createPost(outfitId: 'o1');
    final body = _body(adapter.lastRequest!.data);
    expect(body.containsKey('caption'), isFalse);
    expect(body.containsKey('image_url'), isFalse);
    expect(body['outfit_id'], 'o1');
  });

  test('like / unlike / follow hit the right paths', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );
    final repo = SocialRepository(dio);

    await repo.like('p1');
    expect(adapter.lastRequest!.path, '/v1/social/posts/p1/like');
    expect(adapter.lastRequest!.method, 'POST');

    await repo.unlike('p1');
    expect(adapter.lastRequest!.method, 'DELETE');

    await repo.follow('u2');
    expect(adapter.lastRequest!.path, '/v1/social/follow/u2');
  });

  test('block / unblock and report hit the right paths', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse(<String, Object>{}, status: 204),
    );
    final repo = SocialRepository(dio);

    await repo.block('u2');
    expect(adapter.lastRequest!.path, '/v1/social/block/u2');
    expect(adapter.lastRequest!.method, 'POST');

    await repo.unblock('u2');
    expect(adapter.lastRequest!.method, 'DELETE');

    await repo.report(subjectType: 'post', subjectId: 'p1', reason: 'spam');
    expect(adapter.lastRequest!.path, '/v1/social/reports');
    final body = _body(adapter.lastRequest!.data);
    expect(body['subject_type'], 'post');
    expect(body['subject_id'], 'p1');
    expect(body['reason'], 'spam');
  });

  test('addComment posts the body and parses the comment', () async {
    final (dio, adapter) = fakeDio(
      (_) => jsonResponse({
        'id': 'c1',
        'post_id': 'p1',
        'user_id': 'u1',
        'author_name': 'Mim',
        'body': 'love this',
        'created_at': '2026-06-11T10:05:00Z',
      }),
    );

    final comment = await SocialRepository(dio).addComment('p1', 'love this');
    expect(comment.body, 'love this');
    expect(adapter.lastRequest!.path, '/v1/social/posts/p1/comments');
    expect(_body(adapter.lastRequest!.data)['body'], 'love this');
  });

  test('maps an error envelope to ApiException', () async {
    final (dio, _) = fakeDio(
      (_) => jsonResponse({
        'error': {'code': 'MODERATION_BLOCKED', 'message': 'no'},
      }, status: 422),
    );

    expect(
      () => SocialRepository(dio).createPost(imageUrl: 'x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.moderationBlocked,
        ),
      ),
    );
  });
}
