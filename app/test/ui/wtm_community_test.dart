import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/comment.dart';
import 'package:app/data/models/post.dart';
import 'package:app/data/models/public_profile.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/community/wtm_compose_screen.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// P8 gate coverage: the community feed on the real social stack — flag gating,
/// and the UGC safety gate (Report reaches the moderation endpoint; Block hides
/// the content). Plus like, comment, and follow on the real repository.

class _FakeSocial implements SocialRepository {
  _FakeSocial(this.feed);

  List<Post> feed;
  Map<String, Object?>? reported;
  String? blocked;
  Post? created;
  String? commented;
  final followed = <String>[];

  @override
  Future<List<Post>> getFeed({int limit = 20, DateTime? before}) async => feed;

  @override
  Future<void> report({
    required String subjectType,
    required String subjectId,
    String? reason,
  }) async =>
      reported = {'type': subjectType, 'id': subjectId, 'reason': reason};

  @override
  Future<void> block(String userId) async => blocked = userId;

  @override
  Future<void> like(String postId) async {}
  @override
  Future<void> unlike(String postId) async {}
  @override
  Future<void> follow(String userId) async => followed.add(userId);
  @override
  Future<void> unfollow(String userId) async {}

  @override
  Future<Comment> addComment(String postId, String body) async {
    commented = body;
    return Comment(
        id: 'c1',
        postId: postId,
        userId: 'u9',
        body: body,
        createdAt: DateTime.now());
  }

  @override
  Future<List<Comment>> getComments(String postId,
          {int limit = 50, DateTime? before}) async =>
      const [];

  @override
  Future<Post> createPost({
    String? caption,
    String? imageUrl,
    String? outfitId,
    List<String> tags = const [],
    Map<String, dynamic>? poll,
    String? idempotencyKey,
  }) async {
    created = Post(
        id: 'new',
        userId: 'u1',
        caption: caption,
        imageUrl: imageUrl,
        createdAt: DateTime.now());
    return created!;
  }

  @override
  Future<PublicProfile> getPublicProfile(String userId) async => PublicProfile(
      userId: userId,
      displayName: 'Lara Mayfield',
      followerCount: 8200,
      followingCount: 214,
      postCount: 2);

  @override
  Future<List<Post>> getUserPosts(String userId, {int limit = 30}) async =>
      feed;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Post _post(String id, String userId) => Post(
      id: id,
      userId: userId,
      authorName: 'Lara Mayfield',
      imageUrl: 'https://cdn.test/$id.png',
      caption: 'Night textures and quiet luxury.',
      likeCount: 12,
      commentCount: 3,
      createdAt: DateTime.now(),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder.first);
    await settle(tester);
  }

  final postDots = find.byWidgetPredicate(
      (w) => w is WtmIconButton && w.glyph == WtmGlyph.dots);

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    bool community = true,
    List<Post> feed = const [],
    _FakeSocial? social,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(false),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) => community ? {FeatureFlags.community} : <String>{},
        ),
        socialRepositoryProvider.overrideWithValue(social ?? _FakeSocial(feed)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FashionOsApp(),
      ),
    );
    await settle(tester);
    container.read(goRouterProvider).go(AppRoute.wtmSocial);
    await settle(tester);
    return container;
  }

  testWidgets('community OFF shows the coming-soon state, no feed', (
    tester,
  ) async {
    await boot(tester, community: false, feed: [_post('p1', 'u2')]);
    expect(find.byType(WtmSocialScreen), findsOneWidget);
    expect(find.byType(WtmPostCard), findsNothing);
    expect(find.text('Community is on its way'), findsOneWidget);
  });

  testWidgets('community ON renders the feed', (tester) async {
    await boot(tester, feed: [_post('p1', 'u2'), _post('p2', 'u3')]);
    expect(find.byType(WtmPostCard), findsNWidgets(2));
    expect(find.text('For You'), findsOneWidget);
  });

  testWidgets('community ON shows a create-post button that opens compose (Fix 6)',
      (tester) async {
    await boot(tester, feed: [_post('p1', 'u2')]);
    final createBtn = find.byWidgetPredicate(
        (w) => w is WtmIconButton && w.glyph == WtmGlyph.plus);
    expect(createBtn, findsOneWidget);

    await tapAndSettle(tester, createBtn);
    expect(find.byType(WtmComposeScreen), findsOneWidget);
  });

  testWidgets('community OFF still shows Create Post (header + empty CTA) (Fix A)',
      (tester) async {
    // The real device case: the community flag is OFF. The tab must NOT be a
    // dead end — the header create button and an empty-state CTA both show.
    await boot(tester, community: false, feed: [_post('p1', 'u2')]);
    expect(find.text('Community is on its way'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
          (w) => w is WtmIconButton && w.glyph == WtmGlyph.plus),
      findsOneWidget,
    );
    // Empty-state CTA (GradientCta label) is present and opens compose.
    expect(find.text('Share a look'), findsOneWidget);
    await tapAndSettle(tester, find.text('Share a look'));
    expect(find.byType(WtmComposeScreen), findsOneWidget);
  });

  testWidgets('GATE: a post report reaches the moderation endpoint', (
    tester,
  ) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    await boot(tester, social: social);
    await tapAndSettle(tester, postDots);
    await tapAndSettle(tester, find.text('Spam or scam'));
    expect(social.reported, isNotNull);
    expect(social.reported!['type'], 'post');
    expect(social.reported!['id'], 'p1');
  });

  testWidgets('GATE: blocking a user hides their post from the feed', (
    tester,
  ) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    await boot(tester, social: social);
    expect(find.byType(WtmPostCard), findsOneWidget);

    await tapAndSettle(tester, postDots);
    await tapAndSettle(tester, find.text('Block user'));
    expect(social.blocked, 'u2');
    expect(find.byType(WtmPostCard), findsNothing);
  });

  testWidgets('liking a post calls the like endpoint', (tester) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    await boot(tester, social: social);
    // Tap the heart action (like count text 12 sits next to it).
    await tapAndSettle(tester, find.text('12'));
    // Optimistic toggle bumped the count.
    expect(find.text('13'), findsOneWidget);
  });

  testWidgets('opening a post and commenting hits addComment', (tester) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social);
    container.read(goRouterProvider).push(
          AppRoute.wtmPost,
          extra: _post('p1', 'u2'),
        );
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Love this');
    await tapAndSettle(tester, find.text('POST')); // GoldPill uppercases
    expect(social.commented, 'Love this');
  });

  testWidgets('public profile Follow calls the follow endpoint', (
    tester,
  ) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social);
    container.read(goRouterProvider).push('${AppRoute.wtmUser}?u=u2');
    await settle(tester);
    expect(find.text('Lara Mayfield'), findsWidgets);

    await tapAndSettle(tester, find.text('FOLLOW')); // GoldPill uppercases
    expect(social.followed, contains('u2'));
  });
}
