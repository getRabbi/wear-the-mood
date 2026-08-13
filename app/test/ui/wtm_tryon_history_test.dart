import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:app/app.dart';
import 'package:app/core/auth/auth_providers.dart';
import 'package:app/core/notifications/notification_routing.dart';
import 'package:app/data/models/app_notification.dart';
import 'package:app/core/router/app_router.dart';
import 'package:app/core/router/routes.dart';
import 'package:app/data/models/tryon_result.dart';
import 'package:app/data/repositories/tryon_repository.dart';
import 'package:app/features/onboarding/onboarding_providers.dart';
import 'package:app/ui/mirror/wtm_tryon_history_screen.dart';
import 'package:app/ui/profile/wtm_looks_screen.dart';
import 'package:app/ui/widgets/widgets.dart';

import '../helpers/fake_tryon_results.dart';

/// Try-On History — the account's generations, and removing one for good.
///
/// The defect this covers is not cosmetic. Completed try-ons have always been
/// persisted server-side (`GET /v1/tryon/results`, 32 rows across 7 accounts in
/// production) and the only screen that read them was the pre-Atelier one,
/// reachable solely from a push deep link. There was no delete at all — so a
/// render somebody regretted stayed on their account with nothing they could do
/// about it.
///
/// Unlike Saved Looks, which is a DEVICE record, this is server state: deleting
/// has to survive a reload rather than hide a tile locally.
TryonResult _result(String id, {String? url = 'https://cdn.test/r.jpg'}) =>
    TryonResult(
      id: id,
      resultImageUrl: url,
      createdAt: DateTime.utc(2026, 8, 10),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester, [int ms = 900]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<(ProviderContainer, FakeTryOnResults)> boot(
    WidgetTester tester, {
    required List<TryonResult> results,
    Future<void> Function(String id)? onDelete,
    String at = AppRoute.wtmTryOnHistory,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fake = FakeTryOnResults(results, onDelete: onDelete);
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        isAuthenticatedProvider.overrideWithValue(true),
        onboardingSeenProvider.overrideWith((ref) => true),
        authUserIdProvider.overrideWithValue('u1'),
        tryOnResultsProvider.overrideWith(() => fake),
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
    return (container, fake);
  }

  Finder tile(String id) => find.byKey(Key('wtm-tryon-open-$id'));
  Finder tileDelete(String id) => find.byKey(Key('wtm-tryon-delete-$id'));

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Delete').last);
    await settle(tester);
  }

  group('reaching the history at all', () {
    testWidgets('a completed generation is on screen', (tester) async {
      await boot(tester, results: [_result('r1'), _result('r2')]);

      expect(find.byType(WtmTryOnHistoryScreen), findsOneWidget);
      expect(tile('r1'), findsOneWidget);
      expect(tile('r2'), findsOneWidget);
    });

    testWidgets('Saved Looks offers the way through to it', (tester) async {
      // "Where are my old try-ons?" is the question somebody arrives on Saved
      // Looks asking, and until now that screen was the whole answer available.
      await boot(tester, results: [_result('r1')], at: AppRoute.wtmLooks);

      expect(find.byType(WtmLooksScreen), findsOneWidget);
      final link = find.byKey(const Key('wtm-looks-history-link'));
      expect(link, findsOneWidget);

      await tester.tap(link);
      await settle(tester);
      expect(find.byType(WtmTryOnHistoryScreen), findsOneWidget);
    });

    testWidgets('a try-on push lands on the WTM screen, not the old one', (
      tester,
    ) async {
      final route = AppNotification(
        id: 'n1',
        type: 'try_on_ready',
        title: 'Your try-on is ready',
        targetType: 'tryon_result',
        targetId: 'r1',
        createdAt: DateTime.utc(2026, 8, 10),
      ).route;
      expect(route, AppRoute.wtmTryOnHistory);

      await boot(tester, results: [_result('r1')], at: route!);
      expect(find.byType(WtmTryOnHistoryScreen), findsOneWidget);
    });
  });

  group('the four states', () {
    testWidgets('empty invites a try-on rather than showing nothing', (
      tester,
    ) async {
      await boot(tester, results: const []);

      expect(find.byType(WtmEmptyState), findsOneWidget);
      expect(find.text('No try-ons yet'), findsOneWidget);
    });

    testWidgets('a result with no image is dropped, never drawn as a hole', (
      tester,
    ) async {
      await boot(tester, results: [_result('r1'), _result('r2', url: null)]);

      expect(tile('r1'), findsOneWidget);
      expect(tile('r2'), findsNothing);
    });

    testWidgets('a failed load offers a retry, not a blank grid', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: (retryCount, error) => null,
        overrides: [
          isAuthenticatedProvider.overrideWithValue(true),
          onboardingSeenProvider.overrideWith((ref) => true),
          authUserIdProvider.overrideWithValue('u1'),
          tryOnResultsProvider.overrideWith(FailingTryOnResults.new),
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
      container.read(goRouterProvider).push(AppRoute.wtmTryOnHistory);
      await settle(tester);

      expect(find.byType(WtmErrorState), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('deleting a result', () {
    testWidgets('every tile carries a delete action', (tester) async {
      await boot(tester, results: [_result('r1'), _result('r2')]);

      expect(tileDelete('r1'), findsOneWidget);
      expect(tileDelete('r2'), findsOneWidget);
    });

    testWidgets('it confirms before removing anything', (tester) async {
      final (_, fake) = await boot(tester, results: [_result('r1')]);

      await tester.tap(tileDelete('r1'));
      await settle(tester);

      expect(find.text('Delete this try-on?'), findsOneWidget);
      expect(
        find.textContaining('Your photo and the garment stay where they are.'),
        findsOneWidget,
        reason: 'the render is deleted; its SOURCES are shared and are not',
      );
      expect(
        fake.deleted,
        isEmpty,
        reason: 'nothing may go before the confirmation is answered',
      );
    });

    testWidgets('cancel leaves the result exactly where it was', (
      tester,
    ) async {
      final (_, fake) = await boot(tester, results: [_result('r1')]);

      await tester.tap(tileDelete('r1'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(fake.deleted, isEmpty);
      expect(tile('r1'), findsOneWidget);
      // Usable again — cancelling must not strand the tile.
      expect(tester.widget<WtmIconButton>(tileDelete('r1')).onTap, isNotNull);
    });

    testWidgets('confirming removes the tile and calls the server', (
      tester,
    ) async {
      final (_, fake) = await boot(
        tester,
        results: [_result('r1'), _result('r2')],
      );

      await tester.tap(tileDelete('r1'));
      await settle(tester);
      await confirm(tester);

      expect(fake.deleted, ['r1']);
      expect(tile('r1'), findsNothing);
      expect(
        tile('r2'),
        findsOneWidget,
        reason: 'deleting one result must not disturb the rest of the grid',
      );
    });

    testWidgets('a failed delete puts the result back and says so', (
      tester,
    ) async {
      // A cosmetic deletion is worse than a refused one: the row is still on
      // the account, and the user has been told otherwise.
      await boot(
        tester,
        results: [_result('r1')],
        onDelete: (_) async => throw StateError('offline'),
      );

      await tester.tap(tileDelete('r1'));
      await settle(tester);
      await confirm(tester);

      expect(tile('r1'), findsOneWidget);
      expect(
        find.text("Couldn't delete that try-on. Please try again."),
        findsOneWidget,
      );
    });

    testWidgets('a deleted result does not come back on a rebuild', (
      tester,
    ) async {
      final (container, fake) = await boot(
        tester,
        results: [_result('r1'), _result('r2')],
      );

      await tester.tap(tileDelete('r1'));
      await settle(tester);
      await confirm(tester);

      // Refetch — the state the user gets on a refresh, a relaunch, or a
      // sign-in on another device. The row is gone server-side, so it cannot
      // come back; a delete that only hid a tile would fail here.
      container.invalidate(tryOnResultsProvider);
      await settle(tester);

      expect(find.byType(WtmTryOnHistoryScreen), findsOneWidget);
      expect(tile('r1'), findsNothing);
      expect(tile('r2'), findsOneWidget);
      expect(fake.deleted, ['r1']);
    });

    testWidgets('a second tap while the confirmation is open is ignored', (
      tester,
    ) async {
      final (_, fake) = await boot(tester, results: [_result('r1')]);

      await tester.tap(tileDelete('r1'));
      await tester.pump();
      expect(
        tester.widget<WtmIconButton>(tileDelete('r1')).onTap,
        isNull,
        reason:
            'a second confirmation stacked on the first is where '
            '"did that work?" comes from',
      );
      await settle(tester);
      await confirm(tester);
      expect(fake.deleted, ['r1']);
    });
  });
}
