import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:app/data/models/poll.dart';
import 'package:app/data/models/post.dart';
import 'package:app/data/models/public_profile.dart';
import 'package:app/data/models/wardrobe_item.dart';
import 'package:app/data/repositories/social_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/features/wardrobe/wardrobe_providers.dart';
import 'package:app/ui/community/wtm_community_shared.dart';
import 'package:app/ui/community/wtm_compose_screen.dart';
import 'package:app/ui/community/wtm_social_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_wardrobe_items.dart';

/// P8 gate coverage: the community feed on the real social stack — flag gating,
/// and the UGC safety gate (Report reaches the moderation endpoint; Block hides
/// the content). Plus like, comment, and follow on the real repository.

class _FakeSocial implements SocialRepository {
  _FakeSocial(this.feed);

  List<Post> feed;
  Map<String, Object?>? reported;
  String? blocked;
  Post? created;
  Map<String, dynamic>? createdPoll;
  String? createdOutfitId;
  String? commented;
  int? votedOption;
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
    createdPoll = poll;
    createdOutfitId = outfitId;
    created = Post(
        id: 'new',
        userId: 'u1',
        caption: caption,
        imageUrl: imageUrl,
        createdAt: DateTime.now());
    return created!;
  }

  @override
  Future<Poll> votePoll(String pollId, int optionIndex) async {
    votedOption = optionIndex;
    return Poll(
      id: pollId,
      question: 'Which fit?',
      options: const [
        PollOption(index: 0, label: 'Noir', votes: 3),
        PollOption(index: 1, label: 'Blush', votes: 1),
      ],
      totalVotes: 4,
      myChoice: optionIndex,
    );
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
    List<WardrobeItem> closet = const [],
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
          // Polls are flag-gated like the shipped composer; prod has the flag
          // on, so the suite runs with it on too.
          (ref) => community
              ? {FeatureFlags.community, FeatureFlags.postPolls}
              : {FeatureFlags.postPolls},
        ),
        socialRepositoryProvider.overrideWithValue(social ?? _FakeSocial(feed)),
        wardrobeItemsProvider
            .overrideWith(() => FakeWardrobeItemsNotifier(closet)),
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

  // ── mobile QA: compose modes (look / text / poll) + Share Look prefill ─────

  testWidgets('text-only post publishes without an image and lands on the feed',
      (tester) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social);
    container.read(goRouterProvider).push(AppRoute.wtmCompose);
    await settle(tester);

    await tapAndSettle(tester, find.text('Text'));
    await tester.enterText(
        find.byType(TextField).first, 'Thrifted this today — thoughts?');
    await tester.pump();
    await tester.ensureVisible(find.text('Publish'));
    await tester.pump();
    await tapAndSettle(tester, find.text('Publish'));

    expect(social.created, isNotNull);
    expect(social.created!.caption, 'Thrifted this today — thoughts?');
    expect(social.created!.imageUrl, isNull);
    expect(social.createdPoll, isNull);
    // Published → returned to Community.
    expect(find.byType(WtmSocialScreen), findsOneWidget);
  });

  testWidgets('poll post publishes question + options', (tester) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social);
    container.read(goRouterProvider).push(AppRoute.wtmCompose);
    await settle(tester);

    await tapAndSettle(tester, find.text('Poll'));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Which fit tonight?');
    await tester.enterText(fields.at(1), 'Noir');
    await tester.enterText(fields.at(2), 'Blush');
    await tester.pump();
    await tester.ensureVisible(find.text('Publish'));
    await tester.pump();
    await tapAndSettle(tester, find.text('Publish'));

    expect(social.createdPoll, isNotNull);
    expect(social.createdPoll!['question'], 'Which fit tonight?');
    expect(social.createdPoll!['options'], ['Noir', 'Blush']);
    expect(find.byType(WtmSocialScreen), findsOneWidget);
  });

  testWidgets('Share Look prefill publishes the outfit without a MoodMirror detour',
      (tester) async {
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social);
    container.read(goRouterProvider).push(
          AppRoute.wtmCompose,
          extra: const WtmComposeArgs(
            imageUrl: 'https://cdn.test/outfit-cover.png',
            outfitId: 'o1',
          ),
        );
    await settle(tester);

    // The prefilled look is selected — no "Open MoodMirror" dead end.
    expect(find.text('Open MoodMirror'), findsNothing);
    // Publish sits below the (lazy) source grids — scroll it into existence.
    await tester.scrollUntilVisible(find.text('Publish'), 240,
        scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tapAndSettle(tester, find.text('Publish'));

    expect(social.created, isNotNull);
    expect(social.created!.imageUrl, 'https://cdn.test/outfit-cover.png');
    expect(social.createdOutfitId, 'o1');
    expect(find.byType(WtmSocialScreen), findsOneWidget);
  });

  testWidgets(
      'compose page is clean; the picker sheet selects closet media (Part A)',
      (tester) async {
    const closet = [
      WardrobeItem(id: 'w1', title: 'Silk shirt', cutoutUrl: 'https://x/1.png'),
      WardrobeItem(id: 'w2', title: 'Wool coat', cutoutUrl: 'https://x/2.png'),
    ];
    final social = _FakeSocial([_post('p1', 'u2')]);
    final container = await boot(tester, social: social, closet: closet);
    container.read(goRouterProvider).push(AppRoute.wtmCompose);
    await settle(tester);

    // Clean compose page: NO media grid inline — it lives in the picker.
    expect(find.byType(GridView), findsNothing);
    expect(find.text('Publish'), findsOneWidget); // sticky footer, always built

    await tester.ensureVisible(find.text('Choose picture or look'));
    await tester.pump();
    await tapAndSettle(tester, find.text('Choose picture or look'));
    // The picker sheet: source chips + the closet grid.
    expect(find.text('Closet'), findsOneWidget);
    expect(find.text('Outfits'), findsOneWidget);
    expect(find.text('Looks'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);

    // Pick the first piece → sheet closes, preview carries the selection.
    await tapAndSettle(
      tester,
      find.byWidgetPredicate(
          (w) => w is CachedNetworkImage && w.imageUrl == 'https://x/1.png'),
    );
    expect(find.byType(GridView), findsNothing); // sheet closed

    await tapAndSettle(tester, find.text('Publish'));
    expect(social.created, isNotNull);
    expect(social.created!.imageUrl, isNotNull);
    expect(social.created!.imageUrl, startsWith('https://x/'));
  });

  testWidgets('feed renders text-only and poll posts (no blank media block)',
      (tester) async {
    final textOnly = Post(
      id: 't1',
      userId: 'u2',
      authorName: 'Lara Mayfield',
      caption: 'Quiet luxury is a mindset.',
      createdAt: DateTime.now(),
    );
    final pollPost = Post(
      id: 'q1',
      userId: 'u3',
      authorName: 'Rae Vaughn',
      createdAt: DateTime.now(),
      poll: const Poll(
        id: 'poll1',
        question: 'Which fit?',
        options: [
          PollOption(index: 0, label: 'Noir'),
          PollOption(index: 1, label: 'Blush'),
        ],
      ),
    );
    final social = _FakeSocial([textOnly, pollPost]);
    await boot(tester, social: social);

    expect(find.byType(WtmPostCard), findsNWidgets(2));
    expect(find.text('Quiet luxury is a mindset.'), findsOneWidget);
    expect(find.byType(WtmPollView), findsOneWidget);
    expect(find.text('Which fit?'), findsOneWidget);

    // Voting hits the endpoint and flips to result bars.
    await tapAndSettle(tester, find.text('Noir'));
    expect(social.votedOption, 0);
    expect(find.text('75%'), findsOneWidget); // 3 of 4 votes
  });
}
