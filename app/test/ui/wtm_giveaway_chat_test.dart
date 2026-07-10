import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/discover/wtm_giveaway_chat_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// Secret Pickup Chat coverage: the giveaway-detail request states (requested /
/// accepted / not selected / given / owner inbox) and the chat screen itself
/// (active with optimistic send, locked with a disabled composer).

class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway({
    required this.detail,
    this.chat,
    this.messages = const [],
    this.requestList = const [],
  });

  Giveaway detail;
  GiveawayPickupChat? chat;
  List<GiveawayChatMessage> messages;
  List<GiveawayClaim> requestList;

  final sent = <String>[];
  final decided = <(String, String)>[];
  final cancelled = <String>[];
  final statusUpdates = <(String, String)>[];
  final reported = <String>[];

  @override
  Future<Giveaway> get(String id) async => detail;

  @override
  Future<List<GiveawayClaim>> claims(String id) async => requestList;

  @override
  Future<void> claim(String id, {String? message}) async {}

  @override
  Future<void> decide(String giveawayId, String claimId, String status) async {
    decided.add((claimId, status));
  }

  @override
  Future<void> cancelClaim(String giveawayId) async {
    cancelled.add(giveawayId);
  }

  @override
  Future<void> updateStatus(String id, String status) async {
    statusUpdates.add((id, status));
  }

  @override
  Future<GiveawayPickupChat?> getChat(String giveawayId) async => chat;

  @override
  Future<List<GiveawayChatMessage>> chatMessages(String chatId) async =>
      messages;

  @override
  Future<GiveawayChatMessage> sendChatMessage(String chatId, String body) async {
    sent.add(body);
    final msg = GiveawayChatMessage(
      id: 'm${sent.length}',
      chatId: chatId,
      senderId: 'u1',
      isMine: true,
      body: body,
      createdAt: DateTime.now(),
    );
    messages = [...messages, msg];
    return msg;
  }

  @override
  Future<void> reportChat(String chatId, {String? reason}) async {
    reported.add(chatId);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Giveaway _giveaway({
  String status = 'available',
  String? myClaimStatus,
  bool isMine = false,
}) =>
    Giveaway(
      id: 'g1',
      ownerId: isMine ? 'u1' : 'u2',
      ownerName: 'Maya',
      title: 'Vintage shoulder bag',
      status: status,
      isMine: isMine,
      myClaimStatus: myClaimStatus,
      createdAt: DateTime.now(),
    );

GiveawayPickupChat _chat({String status = 'active', int daysLeft = 6}) =>
    GiveawayPickupChat(
      id: 'c1',
      giveawayId: 'g1',
      giveawayTitle: 'Vintage shoulder bag',
      ownerId: 'u2',
      requesterId: 'u1',
      otherName: 'Maya',
      isOwner: false,
      status: status,
      approvedAt: DateTime.now().subtract(const Duration(days: 1)),
      expiresAt: DateTime.now().add(Duration(days: daysLeft)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );

GiveawayChatMessage _msg(String id, String body,
        {bool mine = false, bool deleted = false}) =>
    GiveawayChatMessage(
      id: id,
      chatId: 'c1',
      senderId: mine ? 'u1' : 'u2',
      isMine: mine,
      body: deleted ? null : body,
      bodyDeleted: deleted,
      createdAt: DateTime.now(),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<ProviderContainer> boot(
    WidgetTester tester, {
    required _FakeGiveaway repo,
    required String at,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        giveawayRepositoryProvider.overrideWithValue(repo),
        enabledFeatureFlagsProvider
            .overrideWith((ref) async => {FeatureFlags.giveawayChat}),
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
    container.read(goRouterProvider).push(at);
    await settle(tester);
    return container;
  }

  /// Dispose the tree so the chat's poll timer is cancelled before the test
  /// framework checks for pending timers.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('giveaway detail request states', () {
    testWidgets('requested → pill + cancel request', (tester) async {
      final repo = _FakeGiveaway(
          detail: _giveaway(myClaimStatus: 'requested'));
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      expect(find.text('REQUESTED'), findsOneWidget); // GoldPill uppercases
      await tester.tap(find.text('Cancel request'));
      await settle(tester);
      await tester.tap(find.text('Cancel request').last); // confirm dialog
      await settle(tester);
      expect(repo.cancelled, contains('g1'));
    });

    testWidgets('accepted → Open Secret Pickup Chat CTA opens the chat',
        (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(status: 'reserved', myClaimStatus: 'accepted'),
        chat: _chat(),
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      final cta = find.byWidgetPredicate(
          (w) => w is GradientCta && w.label == 'Open Secret Pickup Chat');
      expect(cta, findsOneWidget);

      await tester.tap(cta);
      await settle(tester);
      expect(find.byType(WtmGiveawayChatScreen), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('not selected → quiet note, no request button', (tester) async {
      final repo = _FakeGiveaway(
          detail: _giveaway(status: 'reserved', myClaimStatus: 'not_selected'));
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      expect(find.text('Not selected this time'), findsOneWidget);
      expect(find.text('Request Item'), findsNothing);
    });

    testWidgets('given → Given state for a non-participant', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(status: 'claimed'));
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      expect(find.text('Given'), findsOneWidget);
      expect(find.text('Request Item'), findsNothing);
    });

    testWidgets(
        'owner inbox: pending request shows Accept/Decline; accept confirms '
        'and decides', (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(isMine: true),
        requestList: [
          GiveawayClaim(
            id: 'cl1',
            giveawayId: 'g1',
            claimerId: 'u3',
            claimerName: 'Lin',
            message: 'Would love this!',
            status: 'requested',
            createdAt: DateTime.now(),
          ),
        ],
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      expect(find.text('Lin'), findsOneWidget);
      expect(find.text('Would love this!'), findsOneWidget);

      await tester.tap(find.text('ACCEPT')); // GoldPill uppercases
      await settle(tester);
      expect(find.text('Accept this requester?'), findsOneWidget);
      await tester.tap(find.text('Accept').last);
      await settle(tester);
      expect(repo.decided, contains(('cl1', 'accepted')));
    });

    testWidgets('owner: accepted requester card offers chat + Mark as Given',
        (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(status: 'reserved', isMine: true),
        chat: _chat(),
        requestList: [
          GiveawayClaim(
            id: 'cl1',
            giveawayId: 'g1',
            claimerId: 'u3',
            claimerName: 'Lin',
            status: 'accepted',
            createdAt: DateTime.now(),
          ),
        ],
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayDetail}?id=g1');

      expect(find.text('Pickup with Lin'), findsOneWidget);
      expect(find.text('Open Secret Pickup Chat'), findsOneWidget);

      await tester.tap(find.text('Mark as Given'));
      await settle(tester);
      await tester.tap(find.text('Mark as Given').last); // confirm dialog
      await settle(tester);
      expect(repo.statusUpdates, contains(('g1', 'claimed')));
    });
  });

  group('pickup chat screen', () {
    testWidgets(
        'active chat: expiry banner, safety strip, quick chips, optimistic send',
        (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(status: 'reserved', myClaimStatus: 'accepted'),
        chat: _chat(daysLeft: 6),
        messages: [_msg('m0', 'Hi! Is tomorrow ok?')],
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayChat}?id=g1');

      expect(find.byType(WtmGiveawayChatScreen), findsOneWidget);
      expect(find.textContaining('Chat expires in'), findsOneWidget);
      expect(find.textContaining('Keep communication inside Wear The Mood'),
          findsOneWidget);
      expect(find.text('Hi! Is tomorrow ok?'), findsOneWidget);

      // Quick chip sends through the same path (first chip is on-screen; the
      // rest scroll horizontally).
      expect(find.text("I'm on my way."), findsOneWidget);
      await tester.tap(find.text('Can you pick up today?'));
      await settle(tester);
      expect(repo.sent, contains('Can you pick up today?'));
      expect(find.text('Can you pick up today?'), findsNWidgets(2)); // chip + bubble

      // Typed message goes optimistic then lands.
      await tester.enterText(find.byType(TextField), 'See you at 5');
      await tester.tap(find.bySemanticsLabel('Send message'));
      await settle(tester);
      expect(repo.sent, contains('See you at 5'));
      expect(find.text('See you at 5'), findsOneWidget);

      await teardownTree(tester);
    });

    testWidgets('locked chat: locked banner, composer disabled, no chips',
        (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(status: 'claimed', myClaimStatus: 'accepted'),
        chat: _chat(status: 'completed'),
        messages: [_msg('m0', 'Pickup confirmed.', mine: true)],
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayChat}?id=g1');

      expect(find.textContaining('Pickup complete'), findsOneWidget);
      expect(find.text("I'm on my way."), findsNothing); // no quick chips
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });

    testWidgets('expired chat shows redacted messages', (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(status: 'reserved', myClaimStatus: 'accepted'),
        chat: _chat(status: 'expired', daysLeft: 0),
        messages: [_msg('m0', '', deleted: true)],
      );
      await boot(tester, repo: repo, at: '${AppRoute.wtmGiveawayChat}?id=g1');

      expect(find.textContaining('This chat has expired'), findsOneWidget);
      expect(find.text('Message removed'), findsOneWidget);
    });
  });

  group('contact-info nudge', () {
    test('flags phone numbers and emails, ignores normal chat', () {
      expect(looksLikeContactInfo('call me at 01712-345678'), isTrue);
      expect(looksLikeContactInfo('+880 1712 345 678 ok?'), isTrue);
      expect(looksLikeContactInfo('mail me x@y.com'), isTrue);
      expect(looksLikeContactInfo('Meet at 5pm near the gate?'), isFalse);
      expect(looksLikeContactInfo('Tomorrow afternoon works.'), isFalse);
    });
  });
}
