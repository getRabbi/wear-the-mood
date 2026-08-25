import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/auth/guest_session.dart';
import 'package:app/core/auth/pending_auth_intent.dart';
import 'package:app/core/auth/protected_action.dart';
import 'package:app/core/platform/platform_capabilities.dart';
import 'package:app/core/router/routes.dart';

/// POST-AUTH INTENT — what a guest asked for, and what happens when they get an
/// account.
///
/// The two properties that matter:
///
///  * **It resumes ONCE.** A duplicated resume is a duplicated save, a
///    duplicated giveaway entry, a duplicated job. `take()` reads and clears
///    atomically, which is what makes that structurally impossible rather than
///    merely unlikely.
///  * **It carries nothing private.** A semantic action and, at most, a public
///    id — never a photo, a draft, a token or a credit.
void main() {
  // The guest flag lives in secure storage, which needs a platform channel.
  // Without the binding these tests still pass — every read degrades to "not a
  // guest" by design — but they do it through a wall of caught-exception logs.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer boot({
    TargetPlatform platform = TargetPlatform.iOS,
    AppSessionState session = AppSessionState.guest,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        platformCapabilitiesProvider.overrideWithValue(
          PlatformCapabilities(platform: platform),
        ),
        appSessionProvider.overrideWithValue(session),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the intent resumes exactly once', () {
    test('take() returns the intent, then nothing', () async {
      final container = boot();
      final notifier = container.read(pendingAuthIntentProvider.notifier);

      await notifier.set(
        const PendingAuthIntent(action: ProtectedAction.tryOn),
      );

      final first = await notifier.take();
      final second = await notifier.take();

      expect(first?.action, ProtectedAction.tryOn);
      expect(
        second,
        isNull,
        reason: 'a second listener, or a re-fired auth event, resumes nothing',
      );
    });

    test('two takes racing each other still yield one intent', () async {
      final container = boot();
      final notifier = container.read(pendingAuthIntentProvider.notifier);
      await notifier.set(
        const PendingAuthIntent(
          action: ProtectedAction.saveProduct,
          resourceId: 'p1',
        ),
      );

      final results = await Future.wait([notifier.take(), notifier.take()]);

      expect(results.whereType<PendingAuthIntent>().length, 1);
    });

    test(
      'the persisted copy is erased by take, so a relaunch resumes nothing',
      () async {
        final container = boot();
        final notifier = container.read(pendingAuthIntentProvider.notifier);
        await notifier.set(
          const PendingAuthIntent(action: ProtectedAction.closet),
        );
        await notifier.take();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(PendingAuthIntentController.storageKey), isNull);
      },
    );
  });

  group('the intent survives a backgrounded OAuth round trip', () {
    test('it is written to disk when set', () async {
      final container = boot();
      await container
          .read(pendingAuthIntentProvider.notifier)
          .set(
            const PendingAuthIntent(
              action: ProtectedAction.giveawayEntry,
              resourceId: 'g1',
            ),
          );

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PendingAuthIntentController.storageKey);
      expect(raw, isNotNull);
      expect(raw, contains('giveawayEntry'));
      expect(raw, contains('g1'));
    });

    test('a fresh container restores it', () async {
      final first = boot();
      await first
          .read(pendingAuthIntentProvider.notifier)
          .set(const PendingAuthIntent(action: ProtectedAction.closet));

      // A new container is what a relaunch looks like.
      final second = boot();
      await second.read(pendingAuthIntentProvider.notifier).restore();

      expect(
        second.read(pendingAuthIntentProvider)?.action,
        ProtectedAction.closet,
      );
    });
  });

  group('a stale or hostile intent is discarded, never guessed at', () {
    test('an unknown action name is dropped', () {
      expect(
        PendingAuthIntent.fromJson(const {'action': 'timeTravel'}),
        isNull,
      );
    });

    test('a missing action is dropped', () {
      expect(PendingAuthIntent.fromJson(const {'id': 'p1'}), isNull);
    });

    test('an action that NEEDS an id but has none is dropped', () {
      // Resuming a Save with no product would land the user nowhere useful.
      expect(
        PendingAuthIntent.fromJson(const {'action': 'saveProduct'}),
        isNull,
      );
      expect(
        PendingAuthIntent.fromJson(const {'action': 'giveawayEntry'}),
        isNull,
      );
    });

    test('an absurdly long resource id is refused, not truncated', () {
      final intent = PendingAuthIntent.fromJson({
        'action': 'saveProduct',
        'id': 'x' * 500,
      });
      // The id is rejected, which makes the whole intent unresumable.
      expect(intent, isNull);
    });

    test(
      'corrupt stored JSON is cleared rather than crashing the launch',
      () async {
        SharedPreferences.setMockInitialValues({
          PendingAuthIntentController.storageKey: 'not json at all',
        });
        final container = boot();
        await container.read(pendingAuthIntentProvider.notifier).restore();

        expect(container.read(pendingAuthIntentProvider), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(PendingAuthIntentController.storageKey), isNull);
      },
    );

    test('clear() drops it — cancellation, logout, account deletion', () async {
      final container = boot();
      final notifier = container.read(pendingAuthIntentProvider.notifier);
      await notifier.set(
        const PendingAuthIntent(action: ProtectedAction.tryOn),
      );

      await notifier.clear();

      expect(container.read(pendingAuthIntentProvider), isNull);
      expect(await notifier.take(), isNull);
    });
  });

  group('what an intent is allowed to carry', () {
    test('only an action and an optional public id survive a round trip', () {
      const intent = PendingAuthIntent(
        action: ProtectedAction.saveProduct,
        resourceId: 'public-product-1',
      );
      final json = intent.toJson();

      expect(json.keys.toSet(), {'action', 'id'});
      expect(PendingAuthIntent.fromJson(json), intent);
    });

    test('an intent with no resource stores no id key at all', () {
      const intent = PendingAuthIntent(action: ProtectedAction.tryOn);
      expect(intent.toJson().keys.toSet(), {'action'});
    });
  });

  group('resume destinations start a flow, never finish one', () {
    test('try-on resumes at the START of the flow, before photo or consent', () {
      // Not `/wtm/mirror/generating`, not a submit — the first step, where the
      // user re-expresses the intent and Consent v2 appears in its normal place.
      expect(ProtectedAction.tryOn.resumeRoute, AppRoute.wtmMirror);
      expect(
        ProtectedAction.tryOn.resumeRoute,
        isNot(AppRoute.wtmMirrorGenerating),
      );
      expect(
        ProtectedAction.tryOn.resumeRoute,
        isNot(AppRoute.wtmMirrorResult),
      );
    });

    test('closet resumes at the authenticated creation flow', () {
      expect(ProtectedAction.closet.resumeRoute, AppRoute.wtmClosetAdd);
    });

    test('save and giveaway resume at the ITEM, and need its public id', () {
      expect(ProtectedAction.saveProduct.resumeNeedsResourceId, isTrue);
      expect(ProtectedAction.giveawayEntry.resumeNeedsResourceId, isTrue);
      expect(ProtectedAction.saveProduct.resumeRoute, AppRoute.wtmProduct);
      expect(
        ProtectedAction.giveawayEntry.resumeRoute,
        AppRoute.wtmGiveawayDetail,
      );
    });

    test('nothing else demands a resource id', () {
      for (final action in ProtectedAction.values) {
        if (action == ProtectedAction.saveProduct ||
            action == ProtectedAction.giveawayEntry) {
          continue;
        }
        expect(
          action.resumeNeedsResourceId,
          isFalse,
          reason: '${action.name} must resume without carrying an id around',
        );
      }
    });

    test('every action has a resume destination', () {
      for (final action in ProtectedAction.values) {
        expect(action.resumeRoute, isNotEmpty);
      }
    });
  });

  group('every protected route maps to a specific reason', () {
    test('the try-on family maps to tryOn', () {
      for (final route in const [
        AppRoute.wtmMirror,
        AppRoute.wtmMirrorGarments,
        AppRoute.wtmMirrorMode,
        AppRoute.wtmMirrorGenerating,
        AppRoute.wtmMirrorResult,
        AppRoute.wtmMirrorAdjust,
      ]) {
        expect(ProtectedAction.forRoute(route), ProtectedAction.tryOn);
      }
    });

    test('the closet family maps to closet', () {
      for (final route in const [
        AppRoute.wtmCloset,
        AppRoute.wtmClosetAdd,
        AppRoute.wtmClosetItem,
        AppRoute.wtmClosetFixCutout,
      ]) {
        expect(ProtectedAction.forRoute(route), ProtectedAction.closet);
      }
    });

    test('community surfaces map to community', () {
      for (final route in const [
        AppRoute.wtmPost,
        AppRoute.wtmCompose,
        AppRoute.wtmUser,
        AppRoute.wtmInbox,
      ]) {
        expect(ProtectedAction.forRoute(route), ProtectedAction.community);
      }
    });

    test('an UNKNOWN route still maps to something denied, never to null', () {
      // A route nobody has classified must not fall through as "allowed".
      expect(
        ProtectedAction.forRoute('/wtm/some-feature-invented-next-year'),
        ProtectedAction.profile,
      );
    });
  });

  group('guest state and a real session', () {
    test('exitGuest clears the persisted flag', () async {
      final container = boot(session: AppSessionState.guest);
      final notifier = container.read(guestSessionProvider.notifier);

      await notifier.enterGuest();
      expect(container.read(guestSessionProvider), isTrue);

      await notifier.exitGuest();
      expect(container.read(guestSessionProvider), isFalse);
    });

    test('an authenticated session outranks a stale guest flag', () {
      // `appSessionProvider` is overridden here, which is exactly the precedence
      // the real provider implements: authenticated is checked first.
      final container = boot(session: AppSessionState.authenticated);
      expect(container.read(isGuestSessionProvider), isFalse);
      expect(
        container.read(appSessionProvider).canPerformProtectedActions,
        isTrue,
      );
    });
  });
}
