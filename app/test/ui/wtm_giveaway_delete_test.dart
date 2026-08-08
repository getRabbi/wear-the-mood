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
import 'package:app/ui/discover/wtm_giveaways_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

/// Owner delete on the SHIPPING screen.
///
/// The first delete implementation went into `features/giveaway/
/// giveaway_detail_screen.dart`, which production navigation never reaches —
/// it compiled, shipped, and was invisible on a real device. Repository-level
/// tests could not catch that, because the repository was never the broken
/// part. So every test here boots the real app and pushes the real registered
/// route, `/wtm/giveaways/detail?id=...`, and asserts against what that route
/// actually renders.
class _FakeGiveaway implements GiveawayRepository {
  _FakeGiveaway({required this.detail, this.detailError, this.deleteError});

  Giveaway detail;

  /// Thrown by [get] instead of returning [detail] — the deleted-link case.
  Object? detailError;
  Object? deleteError;

  final deleted = <String>[];
  int getCalls = 0;
  int claimsCalls = 0;
  int browseCalls = 0;
  int mineCalls = 0;
  int requestedCalls = 0;

  @override
  Future<Giveaway> get(String id) async {
    getCalls++;
    if (detailError != null) throw detailError!;
    return detail;
  }

  @override
  Future<List<GiveawayClaim>> claims(String id) async {
    claimsCalls++;
    return const [];
  }

  @override
  Future<List<Giveaway>> browse({String? category, String? size}) async {
    browseCalls++;
    return const [];
  }

  @override
  Future<List<Giveaway>> mine() async {
    mineCalls++;
    return const [];
  }

  @override
  Future<List<Giveaway>> requested() async {
    requestedCalls++;
    return const [];
  }

  @override
  Future<void> delete(String giveawayId) async {
    // Recorded BEFORE the failure so a failing delete is still provably one
    // call — the point of the double-tap test is the count, not the outcome.
    deleted.add(giveawayId);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<GiveawayPickupChat?> getChat(String giveawayId) async => null;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

Giveaway _giveaway({bool isMine = true, String status = 'available'}) =>
    Giveaway(
      id: 'g1',
      ownerId: isMine ? 'u1' : 'u2',
      ownerName: 'Maya',
      title: 'Vintage shoulder bag',
      status: status,
      isMine: isMine,
      createdAt: DateTime.now(),
    );

ApiException _api(int status, {String message = 'Request failed.'}) =>
    ApiException(
      code: status == 404 ? ApiErrorCode.notFound : ApiErrorCode.providerError,
      message: message,
      statusCode: status,
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
    String at = '${AppRoute.wtmGiveawayDetail}?id=g1',
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      // No Riverpod auto-retry: an error fixture must stay an error.
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
    container.read(goRouterProvider).push(at);
    await settle(tester);
    return container;
  }

  final deleteButton = find.byKey(const Key('wtm-giveaway-delete'));

  group('owner delete — visibility on the real WTM route', () {
    testWidgets('owner sees Delete giveaway on /wtm/giveaways/detail', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      // The route really did render the shipping screen, not the legacy one.
      expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
      expect(deleteButton, findsOneWidget);
      expect(find.text('Delete giveaway'), findsOneWidget);
    });

    testWidgets('a requester never sees it', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(isMine: false));
      await boot(tester, repo: repo);

      expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
      expect(deleteButton, findsNothing);
      expect(find.text('Delete giveaway'), findsNothing);
    });

    testWidgets('still offered once the item has been given away', (
      tester,
    ) async {
      // A finished listing is exactly the one an owner wants to clear out.
      final repo = _FakeGiveaway(detail: _giveaway(status: 'claimed'));
      await boot(tester, repo: repo);

      expect(deleteButton, findsOneWidget);
    });
  });

  group('owner delete — confirmation', () {
    testWidgets('tapping Delete opens a destructive confirmation', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      await tester.tap(deleteButton);
      await settle(tester);

      expect(find.text('Delete permanently'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.textContaining('It cannot be undone.'),
        findsOneWidget,
        reason: 'the dialog must state that this is irreversible',
      );
      // Nothing has happened yet.
      expect(repo.deleted, isEmpty);
    });

    testWidgets('Cancel makes zero delete calls and keeps the detail open', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      await tester.tap(deleteButton);
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(repo.deleted, isEmpty);
      expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
      expect(find.text('Vintage shoulder bag'), findsWidgets);
      // And the action is usable again — cancelling must not strand the button.
      expect(
        tester.widget<GhostButton>(deleteButton).onPressed,
        isNotNull,
        reason: 'cancel must release the in-flight latch',
      );
    });

    testWidgets('confirming issues exactly one DELETE', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      await tester.tap(deleteButton);
      await settle(tester);
      await tester.tap(find.text('Delete permanently'));
      await settle(tester);

      expect(repo.deleted, ['g1']);
    });

    testWidgets('a double tap cannot open two confirmations or send two', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      // Two taps in the same frame, before any dialog can settle.
      await tester.tap(deleteButton, warnIfMissed: false);
      await tester.tap(deleteButton, warnIfMissed: false);
      await settle(tester);

      expect(
        find.text('Delete permanently'),
        findsOneWidget,
        reason: 'the latch is taken before the dialog, not after it',
      );
      await tester.tap(find.text('Delete permanently'));
      await settle(tester);
      expect(repo.deleted, ['g1']);
    });
  });

  group('owner delete — outcome', () {
    testWidgets('success invalidates the giveaway lists', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      final container = await boot(tester, repo: repo);

      // Hold the lists open so an invalidate forces a real refetch instead of
      // being a no-op on an unwatched autoDispose provider.
      container.listen(giveawayBrowseProvider, (_, _) {});
      container.listen(myGiveawaysProvider, (_, _) {});
      container.listen(requestedGiveawaysProvider, (_, _) {});
      container.listen(giveawayDetailProvider('g1'), (_, _) {});
      container.listen(giveawayClaimsProvider('g1'), (_, _) {});
      await settle(tester);
      final before = (
        repo.browseCalls,
        repo.mineCalls,
        repo.requestedCalls,
        repo.getCalls,
        repo.claimsCalls,
      );

      await tester.tap(deleteButton);
      await settle(tester);
      await tester.tap(find.text('Delete permanently'));
      await settle(tester);

      expect(repo.browseCalls, greaterThan(before.$1));
      expect(repo.mineCalls, greaterThan(before.$2));
      expect(repo.requestedCalls, greaterThan(before.$3));
      expect(repo.getCalls, greaterThan(before.$4));
      expect(repo.claimsCalls, greaterThan(before.$5));
    });

    testWidgets('success leaves the detail for the Giveaways screen', (
      tester,
    ) async {
      final repo = _FakeGiveaway(detail: _giveaway());
      await boot(tester, repo: repo);

      await tester.tap(deleteButton);
      await settle(tester);
      await tester.tap(find.text('Delete permanently'));
      await settle(tester);

      expect(find.byType(WtmGiveawayDetailScreen), findsNothing);
      expect(find.byType(WtmGiveawaysScreen), findsOneWidget);
      // The confirmation has to survive the navigation to be worth showing.
      expect(find.text('Giveaway deleted'), findsOneWidget);
    });

    testWidgets('a failed delete stays on the detail and explains itself', (
      tester,
    ) async {
      final repo = _FakeGiveaway(
        detail: _giveaway(),
        deleteError: _api(500, message: 'Server exploded.'),
      );
      await boot(tester, repo: repo);

      await tester.tap(deleteButton);
      await settle(tester);
      await tester.tap(find.text('Delete permanently'));
      await settle(tester);

      expect(repo.deleted, ['g1']);
      // The listing must NOT be dropped optimistically.
      expect(find.byType(WtmGiveawayDetailScreen), findsOneWidget);
      expect(find.text('Vintage shoulder bag'), findsWidgets);
      expect(find.text('Server exploded.'), findsOneWidget);
      // Recoverable: the owner can try again.
      expect(tester.widget<GhostButton>(deleteButton).onPressed, isNotNull);
    });
  });

  group('deleted link', () {
    testWidgets('404 shows the unavailable copy, not an endless Retry', (
      tester,
    ) async {
      // Arriving from an old notification or a shared link after the owner
      // deleted the listing.
      final repo = _FakeGiveaway(detail: _giveaway(), detailError: _api(404));
      await boot(tester, repo: repo);

      expect(
        find.textContaining('This giveaway is no longer available'),
        findsOneWidget,
      );
      expect(find.byType(WtmErrorState), findsNothing);
      expect(
        find.text('Try again'),
        findsNothing,
        reason: '404 is permanent — retry can never succeed',
      );
      // Not a dead end either.
      expect(find.text('Browse'), findsWidgets);
    });

    testWidgets('a non-404 error keeps normal Retry behaviour', (tester) async {
      final repo = _FakeGiveaway(detail: _giveaway(), detailError: _api(503));
      await boot(tester, repo: repo);

      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.textContaining('This giveaway is no longer available'),
        findsNothing,
        reason: 'a transient outage must not be reported as a deletion',
      );

      // And retry actually refetches.
      final before = repo.getCalls;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(repo.getCalls, greaterThan(before));
    });
  });
}
