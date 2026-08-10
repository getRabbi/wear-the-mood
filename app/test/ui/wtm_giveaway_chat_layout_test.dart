import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/flags/feature_flags.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/giveaway.dart';
import 'package:app/data/repositories/giveaway_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/discover/wtm_giveaway_chat_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// Where things SIT in the pickup chat.
///
/// The report was that notification-type messages appear in or around the
/// typing box. Three separate things put app-authored copy there: a permanent
/// safety strip pinned above the composer, a contact warning rendered inside
/// the composer bar, and system events drawn as gold pills — the app's tappable
/// GoldPill — a few dp above the quick-reply chips. These tests pin the geometry
/// so none of that can come back.
class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway({
    required this.detail,
    this.chat,
    this.messages = const [],
    this.messagesError,
    this.sendError,
  });

  Giveaway detail;
  GiveawayPickupChat? chat;
  List<GiveawayChatMessage> messages;

  /// Thrown by [chatMessages] on every call AFTER the first load.
  Object? messagesError;
  Object? sendError;

  bool _loaded = false;
  int messageCalls = 0;
  final sent = <String>[];

  @override
  Future<Giveaway> get(String id) async => detail;

  @override
  Future<List<GiveawayClaim>> claims(String id) async => const [];

  @override
  Future<GiveawayPickupChat?> getChat(String giveawayId) async => chat;

  @override
  Future<List<GiveawayChatMessage>> chatMessages(String chatId) async {
    messageCalls++;
    if (_loaded && messagesError != null) throw messagesError!;
    _loaded = true;
    return messages;
  }

  @override
  Future<GiveawayChatMessage> sendChatMessage(
    String chatId,
    String body,
  ) async {
    sent.add(body);
    if (sendError != null) throw sendError!;
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
  Future<List<Giveaway>> browse({String? category, String? size}) async =>
      const [];

  @override
  Future<List<Giveaway>> mine() async => const [];

  @override
  Future<List<Giveaway>> requested() async => const [];

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Giveaway _giveaway() => Giveaway(
  id: 'g1',
  ownerId: 'u2',
  ownerName: 'Maya',
  title: 'Vintage shoulder bag',
  status: 'reserved',
  myClaimStatus: 'accepted',
  chatId: 'c1',
  createdAt: DateTime.now(),
);

GiveawayPickupChat _chat({String status = 'active'}) => GiveawayPickupChat(
  id: 'c1',
  giveawayId: 'g1',
  giveawayTitle: 'Vintage shoulder bag',
  ownerId: 'u2',
  requesterId: 'u1',
  otherName: 'Maya',
  isOwner: false,
  status: status,
  approvedAt: DateTime.now().subtract(const Duration(days: 1)),
  expiresAt: DateTime.now().add(const Duration(days: 6)),
  createdAt: DateTime.now().subtract(const Duration(days: 1)),
);

GiveawayChatMessage _msg(
  String id,
  String body, {
  bool mine = false,
  String kind = 'user',
}) => GiveawayChatMessage(
  id: id,
  chatId: 'c1',
  senderId: mine ? 'u1' : 'u2',
  isMine: mine,
  kind: kind,
  body: body,
  createdAt: DateTime.now(),
);

GiveawayChatMessage _system(String id, String body) =>
    _msg(id, body, kind: 'system');

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
    Size size = const Size(1080, 2340),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        giveawayRepositoryProvider.overrideWithValue(repo),
        enabledFeatureFlagsProvider.overrideWith(
          (ref) async => {FeatureFlags.giveawayChat},
        ),
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
    container.read(goRouterProvider).push('${AppRoute.wtmGiveawayChat}?id=g1');
    await settle(tester);
    return container;
  }

  /// Dispose the tree so the chat's poll timer is cancelled before the test
  /// framework checks for pending timers.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  final composer = find.byType(TextField);
  final systemNotice = find.byKey(const Key('wtm-chat-system-notice'));
  final contactWarning = find.byKey(const Key('wtm-chat-contact-warning'));

  double topOf(WidgetTester t, Finder f) => t.getTopLeft(f).dy;
  double bottomOf(WidgetTester t, Finder f) => t.getBottomLeft(f).dy;

  group('system events never touch the composer', () {
    testWidgets('a system-only conversation keeps its notice off the input', (
      tester,
    ) async {
      // The exact shape that produced the report: a freshly accepted request,
      // where every line in the transcript is app-authored.
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_system('s1', 'Maya accepted your request.')],
      );
      await boot(tester, repo: repo);

      expect(find.byType(WtmGiveawayChatScreen), findsOneWidget);
      expect(systemNotice, findsOneWidget);
      expect(
        bottomOf(tester, systemNotice),
        lessThan(topOf(tester, composer)),
        reason: 'a system notice must sit above the composer, never on it',
      );
      await teardownTree(tester);
    });

    testWidgets('the notice is not styled like the tappable quick replies', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_system('s1', 'Pickup confirmed.')],
      );
      await boot(tester, repo: repo);

      // It carries no chip, no pill and no button semantics — the whole reason
      // an unsendable event used to read as something you could tap.
      final noticeChips = find.descendant(
        of: systemNotice,
        matching: find.byType(WtmChip),
      );
      final noticePills = find.descendant(
        of: systemNotice,
        matching: find.byType(GoldPill),
      );
      expect(noticeChips, findsNothing);
      expect(noticePills, findsNothing);
      // And it IS a timeline rule, not a capsule.
      expect(
        find.descendant(of: systemNotice, matching: find.byType(Divider)),
        findsNWidgets(2),
      );
      await teardownTree(tester);
    });

    testWidgets('a system event stays a system event, not a user message', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [
          _system('s1', 'Maya accepted your request.'),
          _msg('m1', 'On my way', mine: true),
        ],
      );
      await boot(tester, repo: repo);

      // Both render, and only the user one is a sided bubble.
      expect(systemNotice, findsOneWidget);
      expect(find.text('Maya accepted your request.'), findsOneWidget);
      expect(find.text('On my way'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('the safety strip left the composer', () {
    testWidgets('it sits with the conversation header, above the messages', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_msg('m1', 'Hi')],
      );
      await boot(tester, repo: repo);

      final safety = find.byKey(const Key('wtm-chat-safety'));
      expect(safety, findsOneWidget);
      expect(
        bottomOf(tester, safety),
        lessThan(topOf(tester, find.text('Hi'))),
        reason: 'safety info is conversation-level, not composer chrome',
      );
      await teardownTree(tester);
    });
  });

  group('the contact warning left the text box', () {
    testWidgets('typing a phone number warns ABOVE the composer surface', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway(), chat: _chat());
      await boot(tester, repo: repo);

      expect(contactWarning, findsNothing);
      await tester.enterText(composer, 'call me on +8801700000000');
      await settle(tester);

      expect(contactWarning, findsOneWidget);
      expect(
        bottomOf(tester, contactWarning),
        lessThanOrEqualTo(topOf(tester, composer)),
        reason: 'the warning must never render inside or over the input',
      );
      await teardownTree(tester);
    });

    testWidgets('the warning never touches what was typed', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(), chat: _chat());
      await boot(tester, repo: repo);

      await tester.enterText(composer, 'ring me: 01700000000');
      await settle(tester);

      expect(contactWarning, findsOneWidget);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'ring me: 01700000000',
        reason: 'a warning is advice, not an edit',
      );
      await teardownTree(tester);
    });

    testWidgets('it disappears once the draft is clean again', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(), chat: _chat());
      await boot(tester, repo: repo);

      await tester.enterText(composer, '+8801700000000');
      await settle(tester);
      expect(contactWarning, findsOneWidget);

      await tester.enterText(composer, 'see you at the gate');
      await settle(tester);
      expect(contactWarning, findsNothing);
      await teardownTree(tester);
    });
  });

  group('composer and keyboard', () {
    testWidgets('the composer stays on screen with the keyboard up', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [for (var i = 0; i < 20; i++) _msg('m$i', 'message $i')],
      );
      await boot(tester, repo: repo);

      // Simulate the keyboard taking the bottom third of the screen.
      tester.view.viewInsets = FakeViewPadding(bottom: 900);
      addTearDown(() => tester.view.resetViewInsets());
      await settle(tester);

      final screenBottom = tester.view.physicalSize.height / 3.0 - 300;
      expect(composer, findsOneWidget);
      expect(
        bottomOf(tester, composer),
        lessThanOrEqualTo(screenBottom + 1),
        reason: 'the input must ride above the keyboard, not under it',
      );
      await teardownTree(tester);
    });

    testWidgets('a multiline draft grows the composer without covering it', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway(), chat: _chat());
      await boot(tester, repo: repo);
      final before = tester.getSize(composer).height;

      await tester.enterText(
        composer,
        'line one\nline two\nline three\nline four',
      );
      await settle(tester);

      expect(tester.getSize(composer).height, greaterThan(before));
      expect(composer.hitTestable(), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('an empty chat still shows a usable composer', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(), chat: _chat());
      await boot(tester, repo: repo);

      expect(find.text('Say hello and arrange the pickup.'), findsOneWidget);
      expect(tester.widget<TextField>(composer).enabled, isTrue);
      await teardownTree(tester);
    });

    testWidgets('a locked chat disables the composer but keeps it in place', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(status: 'expired'),
        messages: [_msg('m1', 'Hi')],
      );
      await boot(tester, repo: repo);

      expect(tester.widget<TextField>(composer).enabled, isFalse);
      await teardownTree(tester);
    });
  });

  group('incoming messages while reading', () {
    testWidgets('a draft survives a poll that brings new messages', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_msg('m1', 'Hi')],
      );
      await boot(tester, repo: repo);

      await tester.enterText(composer, 'half-written reply');
      await settle(tester);

      // The other side says something; the 5s poll picks it up.
      repo.messages = [...repo.messages, _msg('m2', 'You there?')];
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);

      expect(find.text('You there?'), findsOneWidget);
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'half-written reply',
        reason: 'an incoming message must never clear the draft',
      );
      await teardownTree(tester);
    });

    testWidgets('at the bottom, a new message just appears', (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_msg('m1', 'Hi')],
      );
      await boot(tester, repo: repo);

      repo.messages = [...repo.messages, _msg('m2', 'You there?')];
      await tester.pump(const Duration(seconds: 6));
      await settle(tester);

      expect(find.text('You there?'), findsOneWidget);
      expect(
        find.byKey(const Key('wtm-chat-new-messages')),
        findsNothing,
        reason: 'no indicator is needed when it is already on screen',
      );
      await teardownTree(tester);
    });
  });

  group('the giveaway is deleted mid-conversation', () {
    testWidgets('a 404 on poll leaves the chat and says why', (tester) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        messages: [_msg('m1', 'Hi')],
        messagesError: ApiException(
          code: ApiErrorCode.notFound,
          message: 'Not found.',
          statusCode: 404,
        ),
      );
      await boot(tester, repo: repo);
      expect(find.byType(WtmGiveawayChatScreen), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await settle(tester);

      expect(
        find.byType(WtmGiveawayChatScreen),
        findsNothing,
        reason: 'nobody may be left on a conversation that no longer exists',
      );
      expect(
        find.text('This giveaway was deleted by the owner'),
        findsOneWidget,
      );
      await teardownTree(tester);
    });

    testWidgets('sending into a deleted chat leaves rather than dead-ends', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        chat: _chat(),
        sendError: ApiException(
          code: ApiErrorCode.notFound,
          message: 'Not found.',
          statusCode: 404,
        ),
      );
      await boot(tester, repo: repo);

      await tester.enterText(composer, 'still there?');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(find.byType(WtmGiveawayChatScreen), findsNothing);
      expect(
        find.text('This giveaway was deleted by the owner'),
        findsOneWidget,
      );
      await teardownTree(tester);
    });
  });
}
